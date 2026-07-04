module Owner
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_owner!
    before_action :set_sidebar_restaurants

    layout "owner"

    private

    def require_owner!
      require_role!(:owner, :admin)
    end

    def set_sidebar_restaurants
      @sidebar_restaurants = current_user.restaurants.order(:name)
    end
  end
end
