class Subscription < ApplicationRecord
  has_many :subscription_events, dependent: :destroy

  # provisional: 仮開始（クライアント報告のみ。視聴不可）
  # active:      本開始（Apple Webhook 受信済み。視聴可）
  # canceled:    解約済み（expires_at までは視聴可）
  enum :status, {
    provisional: "provisional",
    active: "active",
    canceled: "canceled"
  }, default: "provisional", validate: true

  # transaction_id の一意性は DB のユニーク制約で担保する（サービス層が
  # 事前チェック + RecordNotUnique を処理するため、検証クエリを追加で発行しない）
  validates :transaction_id, presence: true
  validates :product_id, presence: true

  # 視聴可能かどうか。解約済みでも現在の有効期限までは利用可能
  def entitled?
    (active? || canceled?) && expires_at.present? && expires_at.future?
  end

  def as_api_json
    {
      id: id,
      user_id: user_id,
      transaction_id: transaction_id,
      product_id: product_id,
      status: status,
      entitled: entitled?,
      current_period_started_at: current_period_started_at&.iso8601,
      expires_at: expires_at&.iso8601,
      canceled_at: canceled_at&.iso8601
    }
  end
end
