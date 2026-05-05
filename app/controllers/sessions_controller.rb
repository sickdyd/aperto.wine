class SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      if user.confirmed?
        sign_in(user)
        redirect_to stored_location_or(after_sign_in_path(user)), notice: t("auth.signed_in")
      else
        redirect_to sign_in_path, alert: t("auth.not_confirmed")
      end
    else
      flash.now[:alert] = t("auth.invalid_credentials")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out
    redirect_to root_path, notice: t("auth.signed_out")
  end

  private

  def after_sign_in_path(user)
    case user.role
    when "owner" then owner_restaurants_path
    when "admin" then root_path
    else root_path
    end
  end
end
