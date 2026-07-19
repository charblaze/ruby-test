class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      # Apple Webhook が先着した場合はユーザ未紐付けで作成されるため nullable
      t.string :user_id
      t.string :transaction_id, null: false
      t.string :product_id, null: false
      t.string :status, null: false, default: "provisional"
      t.datetime :current_period_started_at
      t.datetime :expires_at
      t.datetime :canceled_at

      t.timestamps
    end

    add_index :subscriptions, :transaction_id, unique: true
    # user_id 単独の検索は複合インデックスの先頭カラムで賄える
    add_index :subscriptions, %i[user_id status]
    add_index :subscriptions, :expires_at
  end
end
