class RegistrationsController < ApplicationController
  def new
    @user = User.new
    @tab = params[:tab].presence || "customer"
  end

  def create
    @user = User.new(registration_params)
    @user.role = registration_role
    @tab = @user.role

    if @user.save
      auto_confirm_in_development!(@user)

      if @user.confirmed?
        sign_in(@user)
        redirect_to after_sign_up_path(@user), notice: t("auth.welcome")
      else
        redirect_to sign_in_path, notice: t("auth.confirmation_sent")
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end

  # Role is set explicitly (never mass-assigned) and restricted to the roles a
  # user may self-select. Anything else (e.g. "admin") falls back to "customer".
  def registration_role
    role = params.dig(:user, :role)
    %w[customer owner].include?(role) ? role : "customer"
  end

  def auto_confirm_in_development!(user)
    user.confirm! if Rails.env.development? || Rails.env.test?
  end

  def after_sign_up_path(user)
    case user.role
    when "owner" then owner_restaurants_path
    when "admin" then root_path
    else root_path
    end
  end
end
