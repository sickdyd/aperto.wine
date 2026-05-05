module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def signed_in?
    current_user.present?
  end

  def authenticate_user!
    unless signed_in?
      store_location
      redirect_to sign_in_path, alert: t("auth.sign_in_required")
    end
  end

  def require_role!(*roles)
    unless roles.any? { |role| current_user&.public_send(:"#{role}?") }
      redirect_to root_path, alert: t("auth.unauthorized")
    end
  end

  def store_location
    session[:return_to] = request.fullpath if request.get? || request.head?
  end

  def stored_location_or(default)
    session.delete(:return_to) || default
  end

  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session.delete(:user_id)
    @current_user = nil
  end
end
