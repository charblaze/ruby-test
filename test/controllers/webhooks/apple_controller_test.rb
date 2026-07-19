require "test_helper"

module Webhooks
  class AppleControllerTest < ActionDispatch::IntegrationTest
    def purchase_payload(overrides = {})
      {
        notification_uuid: "uuid-1",
        type: "PURCHASE",
        transaction_id: "tx_100",
        product_id: "com.samansa.subscription.monthly",
        amount: "3.9",
        currency: "USD",
        purchase_date: "2025-10-01T12:00:00Z",
        expires_date: "2025-11-01T12:00:00Z"
      }.merge(overrides)
    end

    def create_provisional
      Subscription.create!(
        user_id: "user_1",
        transaction_id: "tx_100",
        product_id: "com.samansa.subscription.monthly",
        status: :provisional
      )
    end

    test "PURCHASE activates a provisional subscription (本開始)" do
      subscription = create_provisional

      post webhooks_apple_path, params: purchase_payload
      assert_response :ok

      subscription.reload
      assert_equal "active", subscription.status
      assert_equal Time.iso8601("2025-11-01T12:00:00Z"), subscription.expires_at

      event = subscription.subscription_events.last
      assert_equal "purchase", event.event_type
      assert_equal "uuid-1", event.notification_uuid
      assert_equal 3.9, event.amount.to_f
    end

    test "PURCHASE arriving before the client report creates an unattributed subscription" do
      assert_difference -> { Subscription.count } => 1 do
        post webhooks_apple_path, params: purchase_payload
      end

      assert_response :ok
      subscription = Subscription.last
      assert_nil subscription.user_id
      assert_equal "active", subscription.status
    end

    test "duplicate notification_uuid is a no-op (冪等)" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload

      assert_no_difference -> { SubscriptionEvent.count } do
        post webhooks_apple_path, params: purchase_payload
      end

      assert_response :ok
      assert_equal "already_processed", response.parsed_body["status"]
    end

    test "RENEW extends the current period" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload

      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-2",
        type: "RENEW",
        purchase_date: "2025-11-01T12:00:00Z",
        expires_date: "2025-12-01T12:00:00Z"
      )

      assert_response :ok
      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal "active", subscription.status
      assert_equal Time.iso8601("2025-12-01T12:00:00Z"), subscription.expires_at
    end

    test "a stale RENEW delivered out of order does not rewind the expiry" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-2",
        type: "RENEW",
        purchase_date: "2025-11-01T12:00:00Z",
        expires_date: "2025-12-01T12:00:00Z"
      )

      # 古い期間の通知が遅れて届く
      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-3",
        type: "RENEW",
        purchase_date: "2025-10-01T12:00:00Z",
        expires_date: "2025-11-01T12:00:00Z"
      )

      assert_response :ok
      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal Time.iso8601("2025-12-01T12:00:00Z"), subscription.expires_at
    end

    test "CANCEL keeps entitlement until the current expiry" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload(expires_date: 1.month.from_now.iso8601)

      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-2",
        type: "CANCEL",
        expires_date: nil
      ).compact

      assert_response :ok
      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal "canceled", subscription.status
      assert_not_nil subscription.canceled_at
      assert subscription.entitled?, "解約後も有効期限までは視聴可能"
    end

    test "RENEW after CANCEL reactivates the subscription" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload
      post webhooks_apple_path, params: purchase_payload(notification_uuid: "uuid-2", type: "CANCEL")

      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-3",
        type: "RENEW",
        purchase_date: "2025-11-01T12:00:00Z",
        expires_date: "2025-12-01T12:00:00Z"
      )

      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal "active", subscription.status
      assert_nil subscription.canceled_at
    end

    test "a stale PURCHASE delivered after RENEW does not rewind state" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload(
        notification_uuid: "uuid-2",
        type: "RENEW",
        purchase_date: "2025-11-01T12:00:00Z",
        expires_date: "2025-12-01T12:00:00Z"
      )

      # 最初の PURCHASE 通知が遅れて届く
      post webhooks_apple_path, params: purchase_payload

      assert_response :ok
      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal Time.iso8601("2025-12-01T12:00:00Z"), subscription.expires_at
    end

    test "a stale PURCHASE delivered after CANCEL does not resurrect the subscription" do
      create_provisional
      post webhooks_apple_path, params: purchase_payload(notification_uuid: "uuid-2", type: "RENEW",
                                                        purchase_date: "2025-11-01T12:00:00Z",
                                                        expires_date: "2025-12-01T12:00:00Z")
      post webhooks_apple_path, params: purchase_payload(notification_uuid: "uuid-3", type: "CANCEL")

      post webhooks_apple_path, params: purchase_payload

      assert_response :ok
      subscription = Subscription.find_by!(transaction_id: "tx_100")
      assert_equal "canceled", subscription.status
    end

    test "missing product_id is rejected" do
      post webhooks_apple_path, params: purchase_payload(product_id: nil).compact
      assert_response :unprocessable_entity
    end

    test "unknown notification type is rejected" do
      post webhooks_apple_path, params: purchase_payload(type: "REFUND")
      assert_response :unprocessable_entity
    end

    test "invalid expires_date is rejected" do
      post webhooks_apple_path, params: purchase_payload(expires_date: "not-a-date")
      assert_response :unprocessable_entity
    end
  end
end
