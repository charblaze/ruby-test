module Webhooks
  # Apple のサーバ通知（App Store Server Notifications 相当）を受け付ける。
  # 課題の指定により署名検証は省略。
  class AppleController < ApplicationController
    rescue_from Subscriptions::ApplyAppleNotification::UnsupportedType,
                Subscriptions::ApplyAppleNotification::InvalidPayload do |e|
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def create
      result = Subscriptions::ApplyAppleNotification.new(notification_params).call

      render json: { status: result.duplicate ? "already_processed" : "ok" }
    end

    private

    def notification_params
      params.permit(
        :notification_uuid, :type, :transaction_id, :product_id,
        :amount, :currency, :purchase_date, :expires_date
      ).to_h.symbolize_keys
    end
  end
end
