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

    # Public menu (customer-facing, no auth required)
    get "menu/:id", to: "menus#show", as: :menu
    # Per-table QR entry point: same menu, resolved from the table's token
    get "t/:table_token", to: "menus#show", as: :table_menu

    # Session-backed cart (customer-facing, no auth required)
    get    "menu/:restaurant_id/cart",       to: "carts#show",        as: :cart
    post   "menu/:restaurant_id/cart/items", to: "carts#add_item",    as: :cart_items
    patch  "menu/:restaurant_id/cart/items", to: "carts#update_item"
    delete "menu/:restaurant_id/cart/items", to: "carts#remove_item"
    delete "menu/:restaurant_id/cart",       to: "carts#destroy"

    # Order placement and status (customer-facing, no auth required). The
    # only public write endpoint in the feature — see OrdersController for
    # its abuse controls. public_token is a 24-char base58 has_secure_token,
    # so :public_token gets no digits-only constraint the way an :id would.
    post "menu/:restaurant_id/orders", to: "orders#create", as: :orders
    # No as: here — the post above already defines orders_path for this
    # same URL, and a second :as on the same name would just warn.
    get  "menu/:restaurant_id/orders", to: "orders#index"
    get  "orders/:public_token",       to: "orders#show",   as: :order_status

    # Owner namespace
    namespace :owner do
      # Wine data autofill proxy — not nested under restaurants: wine reference
      # data is global, only the session needs to be an owner.
      resources :wine_lookups, only: [ :index ]

      resources :address_suggestions, only: [ :index ]
      resources :restaurants do
        resources :wines, except: [ :show ]
        resources :wine_lists, except: [ :show ] do
          resources :wine_list_items, only: [ :create, :update, :destroy ] do
            collection do
              patch :sort
              post :create_all
            end
          end
        end
        resource :qr_code, only: [ :show ], controller: "qr_codes"
        resources :tables, except: [ :show ], controller: "restaurant_tables" do
          member do
            get :qr
          end
          collection do
            get :bulk_print
            get :bulk_new
            post :bulk_create
            delete :destroy_all
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
