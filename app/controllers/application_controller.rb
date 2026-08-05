class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Pre-launch gate (jeero pattern): the whole site sits behind HTTP basic auth
  # whenever HTTP_AUTH_USER is set (staging, pre-launch production). Unset the
  # env vars to open the site — no deploy required.
  before_action :http_basic_auth, if: -> { ENV["HTTP_AUTH_USER"].present? }

  around_action :switch_locale

  private

  def http_basic_auth
    authenticate_or_request_with_http_basic do |user, password|
      # to_s: a malformed Basic header (no colon in the decoded payload) yields
      # nil credentials, which would crash secure_compare with a 500 instead of 401.
      ActiveSupport::SecurityUtils.secure_compare(user.to_s, ENV["HTTP_AUTH_USER"].to_s) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, ENV["HTTP_AUTH_PASSWORD"].to_s)
    end
  end

  # Resolution priority, highest first: an explicit :locale param, the choice
  # remembered from an earlier explicit pick, the browser's Accept-Language,
  # then I18n.default_locale (:it). Every source is filtered through
  # #supported_locale, so nothing user-controlled reaches I18n.with_locale,
  # which raises I18n::InvalidLocale — a 500 — on anything unrecognised.
  def switch_locale(&action)
    chosen = supported_locale(params[:locale])
    # Remember explicit picks only. Without this the visitor loses the choice
    # on the next click: default_url_options drops the prefix once the locale
    # matches the default, and Accept-Language then wins the unprefixed request.
    # Only write on an actual change, so repeat visits to a prefixed URL do not
    # ship a fresh Set-Cookie on every response.
    session[:locale] = chosen.to_s if chosen && session[:locale] != chosen.to_s

    locale = chosen || supported_locale(session[:locale]) || locale_from_header || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def locale_from_header
    accept_language = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil unless accept_language

    parsed = accept_language.scan(/([a-z]{2})(?:-[A-Za-z]{2})?/).flatten
    parsed.filter_map { |lang| supported_locale(lang) }.first
  end

  def supported_locale(locale)
    return nil if locale.blank?

    locale.to_s.to_sym if I18n.available_locales.include?(locale.to_s.to_sym)
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
