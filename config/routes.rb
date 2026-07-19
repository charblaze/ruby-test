Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # クライアント -> サーバ（決済完了直後の報告。仮開始）
      resources :subscriptions, only: %i[create]
      # ユーザのサブスクリプション状態の照会（視聴可否の判定に利用）
      resources :users, only: [] do
        resources :subscriptions, only: %i[index], controller: "user_subscriptions"
      end
    end
  end

  namespace :webhooks do
    # Apple -> サーバ（開始・更新・解約の通知）
    post "apple", to: "apple#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
