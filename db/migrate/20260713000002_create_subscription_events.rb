class CreateSubscriptionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :subscription_events do |t|
      # subscription_id 単独の検索は複合インデックスの先頭カラムで賄える
      t.references :subscription, null: false, foreign_key: true, index: false
      t.string :source, null: false
      t.string :event_type, null: false
      # Apple Webhook 由来のイベントのみ持つ。ユニーク制約が冪等性を担保する
      t.string :notification_uuid
      t.decimal :amount, precision: 12, scale: 4
      t.string :currency
      t.datetime :purchase_date
      t.datetime :expires_date
      t.json :payload

      t.timestamps
    end

    add_index :subscription_events, :notification_uuid, unique: true
    add_index :subscription_events, %i[subscription_id event_type]
    add_index :subscription_events, :created_at
  end
end
