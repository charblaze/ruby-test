module Api
  module V1
    # クライアント（アプリ）からの決済完了報告を受け付ける
    class SubscriptionsController < ApplicationController
      REQUIRED_PARAMS = %i[user_id transaction_id product_id].freeze

      rescue_from Subscriptions::ReportPurchase::Conflict do |e|
        render json: { error: e.message }, status: :conflict
      end

      def create
        missing = REQUIRED_PARAMS.select { |key| params[key].blank? }
        if missing.any?
          return render json: { error: "missing required parameters: #{missing.join(', ')}" },
                        status: :unprocessable_entity
        end

        result = Subscriptions::ReportPurchase.new(
          user_id: params[:user_id],
          transaction_id: params[:transaction_id],
          product_id: params[:product_id]
        ).call

        render json: { subscription: result.subscription.as_api_json },
               status: result.created ? :created : :ok
      end
    end
  end
end
