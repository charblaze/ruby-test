require "test_helper"

module Api
  module V1
    class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
      PARAMS = {
        user_id: "user_1",
        transaction_id: "tx_100",
        product_id: "com.samansa.subscription.monthly"
      }.freeze

      test "creates a provisional subscription (仮開始)" do
        assert_difference -> { Subscription.count } => 1, -> { SubscriptionEvent.count } => 1 do
          post api_v1_subscriptions_path, params: PARAMS
        end

        assert_response :created
        body = response.parsed_body["subscription"]
        assert_equal "provisional", body["status"]
        assert_equal false, body["entitled"], "仮開始中は視聴不可"
        assert_equal "user_1", body["user_id"]

        event = SubscriptionEvent.last
        assert_equal "client", event.source
        assert_equal "purchase_reported", event.event_type
      end

      test "is idempotent for the same transaction_id" do
        post api_v1_subscriptions_path, params: PARAMS
        assert_response :created

        assert_no_difference -> { Subscription.count } do
          post api_v1_subscriptions_path, params: PARAMS
        end
        assert_response :ok
      end

      test "rejects a transaction_id already linked to another user" do
        post api_v1_subscriptions_path, params: PARAMS
        post api_v1_subscriptions_path, params: PARAMS.merge(user_id: "user_2")

        assert_response :conflict
      end

      test "claims an unattributed subscription created by an earlier webhook" do
        subscription = Subscription.create!(
          transaction_id: "tx_100", product_id: "p1", status: :active,
          expires_at: 1.month.from_now
        )

        assert_difference -> { SubscriptionEvent.count } => 1 do
          post api_v1_subscriptions_path, params: PARAMS
        end
        assert_response :ok
        assert_equal "user_1", subscription.reload.user_id
        assert_equal "active", subscription.status, "Webhook 先着時の状態は上書きしない"
        assert_equal "purchase_reported", subscription.subscription_events.last.event_type
      end

      test "rejects missing parameters" do
        post api_v1_subscriptions_path, params: { user_id: "user_1" }
        assert_response :unprocessable_entity
        assert_match(/transaction_id/, response.parsed_body["error"])
      end
    end
  end
end
