module Api
  module V1
    # ユーザのサブスクリプション一覧と視聴可否（entitled）を返す
    class UserSubscriptionsController < ApplicationController
      def index
        subscriptions = Subscription.where(user_id: params[:user_id]).order(created_at: :desc)

        render json: {
          subscriptions: subscriptions.map(&:as_api_json),
          entitled: subscriptions.any?(&:entitled?)
        }
      end
    end
  end
end
