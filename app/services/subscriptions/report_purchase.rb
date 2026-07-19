# クライアント（アプリ）からの決済完了報告を受け付け、サブスクリプションを仮開始する。
#
# 冪等性: transaction_id のユニーク制約を利用。同じ transaction_id での再送は
# 既存レコードをそのまま返す（created: false）。
# 順序性: Apple Webhook が先に届いていた場合は既にレコードが存在するので、
# user_id が未紐付けであればここで紐付ける（状態は上書きしない）。
module Subscriptions
  class ReportPurchase
    class Conflict < StandardError; end

    Result = Struct.new(:subscription, :created, keyword_init: true)

    def initialize(user_id:, transaction_id:, product_id:)
      @user_id = user_id
      @transaction_id = transaction_id
      @product_id = product_id
    end

    def call
      attempt_call(allow_retry: true)
    end

    private

    def attempt_call(allow_retry:)
      ActiveRecord::Base.transaction do
        subscription = Subscription.lock.find_by(transaction_id: @transaction_id)
        subscription ? claim(subscription) : create_provisional
      end
    rescue ActiveRecord::RecordNotUnique
      # 同時リクエストで作成が競合した場合は、勝った方のレコードに対して再実行する
      raise unless allow_retry

      attempt_call(allow_retry: false)
    end

    def claim(subscription)
      if subscription.user_id.present? && subscription.user_id != @user_id
        raise Conflict, "transaction_id is already linked to another user"
      end

      if subscription.user_id.blank?
        subscription.update!(user_id: @user_id)
        record_reported_event(subscription)
      end
      Result.new(subscription: subscription, created: false)
    end

    def create_provisional
      subscription = Subscription.create!(
        user_id: @user_id,
        transaction_id: @transaction_id,
        product_id: @product_id,
        status: :provisional
      )
      record_reported_event(subscription)
      Result.new(subscription: subscription, created: true)
    end

    def record_reported_event(subscription)
      subscription.subscription_events.create!(
        source: "client",
        event_type: "purchase_reported",
        payload: {
          user_id: @user_id,
          transaction_id: @transaction_id,
          product_id: @product_id
        }
      )
    end
  end
end
