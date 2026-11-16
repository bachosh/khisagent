Rails.application.routes.draw do
  root "pages#home"

  get "dashboard", to: "dashboard#show"
  patch "locale/:locale", to: "locales#update", as: :locale, constraints: { locale: /ka|en/ }

  # app/controllers/auth: sign in/out, password reset, sign up, profile
  scope module: :auth do
    resource :session
    resources :passwords, param: :token
    resource :registration, only: %i[ new create ]
    resource :profile, only: %i[ edit update ]
  end

  # app/controllers/chat: conversations with the assistant
  scope module: :chat do
    resources :conversations, only: %i[ index new create show update destroy ] do
      resources :messages, only: :create
    end
  end

  # app/controllers/analysis: uploaded statements and their risk reports
  scope module: :analysis do
    resources :statements, only: %i[ index show destroy ] do
      member do
        get :download
        post :reanalyze
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
