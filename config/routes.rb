Rails.application.routes.draw do
  root "pages#home"

  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]
  resource :profile, only: %i[ edit update ]
  patch "locale/:locale", to: "locales#update", as: :locale, constraints: { locale: /ka|en/ }

  get "dashboard", to: "dashboard#show"

  resources :conversations, only: %i[ index new create show update destroy ] do
    resources :messages, only: :create
  end

  resources :statements, only: %i[ index show destroy ] do
    member do
      get :download
      post :reanalyze
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
