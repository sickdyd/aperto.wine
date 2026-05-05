module Owner
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_owner!

    layout "owner"

    private

    def require_owner!
      require_role!(:owner, :admin)
    end
  end
end
