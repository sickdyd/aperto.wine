Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"

  get "up" => "rails/health#show", as: :rails_health_check

  # Temporary: bottle SVG preview (remove after design finalization)
  get "bottles/preview", to: "bottles_preview#index" if Rails.env.development?

  scope "(:locale)", locale: /en|it/ do
    root "home#index"

    # Auth
    get "sign_in", to: "sessions#new", as: :sign_in
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy", as: :sign_out
    get "sign_up", to: "registrations#new", as: :sign_up
    post "sign_up", to: "registrations#create"

    # Public menu (customer-facing, no auth required)
    get "menu/:id", to: "menus#show", as: :menu
    # Per-table QR entry point: same menu, resolved from the table's token
    get "t/:table_token", to: "menus#show", as: :table_menu

    # Owner namespace
    namespace :owner do
      # Wine data autofill proxy — not nested under restaurants: wine reference
      # data is global, only the session needs to be an owner.
      resources :wine_lookups, only: [ :index ]

      resources :address_suggestions, only: [ :index ]
      resources :restaurants do
        resources :wines, except: [ :show ]
        resources :wine_lists, except: [ :show ] do
          collection do
            patch :toggle_all_wines
          end
          resources :wine_list_items, only: [ :create, :update, :destroy ]
        end
        resource :qr_code, only: [ :show ], controller: "qr_codes"
        resources :tables, except: [ :show ], controller: "restaurant_tables" do
          member do
            get :qr
          end
          collection do
            get :bulk_print
          end
        end
        resources :orders, only: [ :index, :show ] do
          member do
            patch :approve
            patch :cancel
          end
        end
      end
    end
  end
end
