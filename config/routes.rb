Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"
  # Health check (outside locale scope)
  get "up" => "rails/health#show", as: :rails_health_check

  scope "(:locale)", locale: /en|it/ do
    root "home#index"
  end
end
