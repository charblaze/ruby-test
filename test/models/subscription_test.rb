require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "provisional subscription is not entitled even if expires_at is in the future" do
    subscription = Subscription.new(status: :provisional, expires_at: 1.month.from_now)
    assert_not subscription.entitled?
  end

  test "active subscription with future expires_at is entitled" do
    subscription = Subscription.new(status: :active, expires_at: 1.month.from_now)
    assert subscription.entitled?
  end

  test "active subscription without expires_at is not entitled" do
    subscription = Subscription.new(status: :active, expires_at: nil)
    assert_not subscription.entitled?
  end

  test "canceled subscription remains entitled until expires_at" do
    subscription = Subscription.new(status: :canceled, expires_at: 1.week.from_now)
    assert subscription.entitled?
  end

  test "canceled subscription past expires_at is not entitled" do
    subscription = Subscription.new(status: :canceled, expires_at: 1.day.ago)
    assert_not subscription.entitled?
  end

  test "transaction_id uniqueness is enforced by the database constraint" do
    Subscription.create!(user_id: "u1", transaction_id: "tx1", product_id: "p1")
    duplicate = Subscription.new(user_id: "u2", transaction_id: "tx1", product_id: "p1")
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end
end
