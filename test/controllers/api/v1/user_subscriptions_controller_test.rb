require "test_helper"

module Api
  module V1
    class UserSubscriptionsControllerTest < ActionDispatch::IntegrationTest
      test "returns the user's subscriptions and overall entitlement" do
        Subscription.create!(
          user_id: "user_1", transaction_id: "tx_1", product_id: "p1",
          status: :canceled, expires_at: 1.week.from_now
        )

        get api_v1_user_subscriptions_path("user_1")
        assert_response :ok

        body = response.parsed_body
        assert_equal 1, body["subscriptions"].size
        assert_equal true, body["entitled"], "解約済みでも期限内なら視聴可能"
      end

      test "returns empty list for unknown user" do
        get api_v1_user_subscriptions_path("nobody")
        assert_response :ok
        assert_empty response.parsed_body["subscriptions"]
        assert_equal false, response.parsed_body["entitled"]
      end
    end
  end
end
