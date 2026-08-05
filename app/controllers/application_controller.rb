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

  # Resolution priority, highest first: an explicit :locale param, an override
  # remembered from an earlier switcher click, then whatever the request
  # negotiates on its own — Accept-Language, falling back to
  # I18n.default_locale (:it). Every source is filtered through
  # #supported_locale, so nothing user-controlled reaches I18n.with_locale,
  # which raises I18n::InvalidLocale — a 500 — on anything it does not know.
  def switch_locale(&action)
    negotiated = locale_from_header || I18n.default_locale
    chosen = supported_locale(params[:locale])
    remember_locale_override(chosen, negotiated) if chosen

    I18n.with_locale(chosen || supported_locale(session[:locale]) || negotiated, &action)
  end

  # Only a locale that departs from what the request negotiates on its own is
  # worth remembering. default_url_options prefixes every internal link with
  # the locale whenever it is not the default, so persisting on the mere
  # presence of the param would turn any ordinary click into a durable
  # preference — and on a shared browser, silently impose it on the next
  # visitor. Picking the negotiated locale is how a visitor drops the override
  # and goes back to being led by their browser.
  def remember_locale_override(chosen, negotiated)
    if chosen == negotiated
      session.delete(:locale)
    else
      session[:locale] = chosen.to_s
    end
  end

  # Accept-Language is ordered by the q-value, not by position (RFC 9110
  # §12.5.4) — a proxy or hand-built request may well list its preferences out
  # of order, and "q=0" means "not acceptable" rather than "least preferred".
  def locale_from_header
    accept_language = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil if accept_language.blank?

    ranked = accept_language.split(",").each_with_index.filter_map do |range, position|
      tag, *parameters = range.split(";").map(&:strip)
      locale = supported_locale(tag.to_s[/\A[A-Za-z]{2}/])
      next unless locale

      quality = parameters.find { |p| p.start_with?("q=") }&.delete_prefix("q=")&.to_f || 1.0
      [ locale, quality, position ] if quality.positive?
    end

    # Highest q wins; ties go to whichever the client listed first.
    ranked.min_by { |_locale, quality, position| [ -quality, position ] }&.first
  end

  def supported_locale(locale)
    return nil if locale.blank?

    locale.to_s.to_sym if I18n.available_locales.include?(locale.to_s.to_sym)
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
