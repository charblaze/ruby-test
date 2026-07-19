class SubscriptionEvent < ApplicationRecord
  SOURCES = %w[client apple_webhook].freeze
  EVENT_TYPES = %w[purchase_reported purchase renew cancel].freeze

  belongs_to :subscription

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  # notification_uuid の一意性は DB のユニーク制約で担保する（冪等性チェックは
  # サービス層の processed? が担うため、検証クエリを追加で発行しない）
end
