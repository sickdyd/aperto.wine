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

    # Legacy numeric menu URL. QR codes printed before slugs existed point
    # here, so it has to keep resolving — it redirects to the restaurant's
    # slug. The digits-only constraint keeps it from swallowing slugs.
    get "menu/:id", to: "menus#legacy", as: :menu, constraints: { id: /\d+/ }

    # Per-table QR entry point: the published menu, resolved from the table's
    # token. Renders in place rather than redirecting to the slug URL, so the
    # table stays attributed even when the browser refuses cookies.
    get "t/:table_token", to: "menus#show", as: :table_menu

    # Session-backed cart (customer-facing, no auth required). Kept under its
    # own "cart/" prefix rather than nested under the restaurant slug: that
    # way no wine list slug can ever collide with "cart" or "orders".
    get    "cart/:restaurant_slug",       to: "carts#show",        as: :cart
    post   "cart/:restaurant_slug/items", to: "carts#add_item",    as: :cart_items
    patch  "cart/:restaurant_slug/items", to: "carts#update_item"
    delete "cart/:restaurant_slug/items", to: "carts#remove_item"
    delete "cart/:restaurant_slug",       to: "carts#destroy"

    # Order placement and status (customer-facing, no auth required). The
    # only public write endpoint in the feature — see OrdersController for
    # its abuse controls. public_token is a 24-char base58 has_secure_token,
    # so :public_token gets no digits-only constraint the way an :id would.
    post "cart/:restaurant_slug/orders", to: "orders#create", as: :orders
    # No as: here — the post above already defines orders_path for this
    # same URL, and a second :as on the same name would just warn.
    get  "cart/:restaurant_slug/orders", to: "orders#index"
    get  "orders/:public_token",         to: "orders#show",   as: :order_status

    # Owner namespace
    namespace :owner do
      # Wine data autofill proxy — not nested under restaurants: wine reference
      # data is global, only the session needs to be an owner.
      resources :wine_lookups, only: [ :index ]

      resources :address_suggestions, only: [ :index ]
      resources :restaurants do
        resources :wines, except: [ :show ]
        resources :wine_lists, except: [ :show ] do
          member do
            # Publishing is one list winning, not a flag being toggled on each
            # — hence a dedicated action rather than an :active attribute.
            patch :publish
          end
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
          # Polled by every open owner page for this restaurant — see
          # Owner::OrdersController#notifications. A collection route rather
          # than a member one: the question is "what has arrived", which no
          # single order can answer.
          collection do
            get :notifications
          end
          member do
            patch :approve
            patch :cancel
          end
        end
      end
    end

    # The public menu, declared last on purpose: ":restaurant_slug" matches a
    # single path segment and would shadow every route above it — "sign_in",
    # "cart", the whole owner namespace — if it came first. Route order is
    # what protects them; Restaurant::RESERVED_SLUGS keeps owners from
    # claiming a slug that could never resolve anyway.
    get ":restaurant_slug",                 to: "menus#show", as: :restaurant_menu
    get ":restaurant_slug/:wine_list_slug", to: "menus#show", as: :wine_list_menu
  end
end
