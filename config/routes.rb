Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"

  get "up" => "rails/health#show", as: :rails_health_check

  scope "(:locale)", locale: /en|it/ do
    root "home#index"

    # Auth
    get "sign_in", to: "sessions#new", as: :sign_in
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy", as: :sign_out
    get "sign_up", to: "registrations#new", as: :sign_up
    post "sign_up", to: "registrations#create"

    # Owner namespace
    namespace :owner do
      resources :restaurants do
        resources :wines, except: [:show]
      end
    end
  end
end
