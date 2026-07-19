# Apple からの Webhook 通知（PURCHASE / RENEW / CANCEL）を適用する。
#
# 冪等性: notification_uuid のユニーク制約を利用。処理済みの通知は
# duplicate: true として何もせず正常応答できるようにする（Apple は再送するため）。
# 順序性:
#   - PURCHASE がクライアント報告より先に届いた場合はユーザ未紐付けの
#     サブスクリプションを作成する（後からクライアント報告で紐付く）。
#   - RENEW は expires_date が現在より進む場合のみ期間を更新する
#     （遅延・逆順で届いた古い通知が期限を巻き戻さないようにする）。
#   - CANCEL は expires_at を変更しない（有効期限までは視聴可能）。
module Subscriptions
  class ApplyAppleNotification
    class UnsupportedType < StandardError; end
    class InvalidPayload < StandardError; end

    TYPE_TO_EVENT = {
      "PURCHASE" => "purchase",
      "RENEW" => "renew",
      "CANCEL" => "cancel"
    }.freeze

    Result = Struct.new(:subscription, :duplicate, keyword_init: true)

    def initialize(payload)
      @payload = payload
    end

    def call
      validate!
      attempt_call(allow_retry: true)
    end

    private

    def attempt_call(allow_retry:)
      return Result.new(duplicate: true) if processed?

      ActiveRecord::Base.transaction do
        subscription = lock_or_create_subscription
        apply(subscription)
        record_event(subscription)
        Result.new(subscription: subscription, duplicate: false)
      end
    rescue ActiveRecord::RecordNotUnique
      # notification_uuid の同時重複（→ 処理済みとして返す）か、
      # subscription 作成の競合（→ 勝った方のレコードに対して一度だけ再実行）
      return Result.new(duplicate: true) if processed?
      raise unless allow_retry

      attempt_call(allow_retry: false)
    end

    def notification_uuid = @payload[:notification_uuid]
    def type = @payload[:type]
    def transaction_id = @payload[:transaction_id]

    def validate!
      raise UnsupportedType, "unsupported type: #{type}" unless TYPE_TO_EVENT.key?(type)

      %i[notification_uuid transaction_id product_id].each do |key|
        raise InvalidPayload, "#{key} is required" if @payload[key].blank?
      end

      if type != "CANCEL" && expires_date.nil?
        raise InvalidPayload, "expires_date is required for #{type}"
      end
    end

    def processed?
      SubscriptionEvent.exists?(notification_uuid: notification_uuid)
    end

    def lock_or_create_subscription
      # 作成直後のレコードは同一トランザクション内で排他済みのためロック再取得は不要
      Subscription.lock.find_by(transaction_id: transaction_id) ||
        Subscription.create!(
          transaction_id: transaction_id,
          product_id: @payload[:product_id],
          status: :provisional
        )
    end

    def apply(subscription)
      case type
      when "PURCHASE", "RENEW" then apply_period_update(subscription)
      when "CANCEL" then apply_cancel(subscription)
      end
    end

    # PURCHASE / RENEW 共通: サブスクリプション期間を前に進めて active にする。
    # 既知の期限より過去の通知は古い（順序逆転した）通知とみなして状態を変えない
    # （RENEW 後や CANCEL 後に遅れて届いた PURCHASE が状態を巻き戻すのを防ぐ）
    def apply_period_update(subscription)
      return if subscription.expires_at.present? && expires_date <= subscription.expires_at

      subscription.update!(
        status: :active,
        product_id: @payload[:product_id] || subscription.product_id,
        current_period_started_at: purchase_date,
        expires_at: expires_date,
        canceled_at: nil
      )
    end

    def apply_cancel(subscription)
      # 有効期限はそのまま。expires_at 未設定（仮開始のまま解約）の場合のみ補完する
      subscription.update!(
        status: :canceled,
        canceled_at: Time.current,
        expires_at: subscription.expires_at || expires_date
      )
    end

    def record_event(subscription)
      subscription.subscription_events.create!(
        source: "apple_webhook",
        event_type: TYPE_TO_EVENT.fetch(type),
        notification_uuid: notification_uuid,
        amount: @payload[:amount],
        currency: @payload[:currency],
        purchase_date: purchase_date,
        expires_date: expires_date,
        payload: @payload
      )
    end

    def purchase_date
      @purchase_date ||= parse_time(:purchase_date)
    end

    def expires_date
      @expires_date ||= parse_time(:expires_date)
    end

    def parse_time(key)
      value = @payload[key]
      return nil if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise InvalidPayload, "#{key} is not a valid ISO8601 datetime"
    end
  end
end
