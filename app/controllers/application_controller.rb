class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :switch_locale
  helper_method :current_user, :sidebar_conversations

  private

  def current_user
    Current.user
  end

  def sidebar_conversations
    @sidebar_conversations ||= current_user ? current_user.conversations.recent.limit(30) : []
  end

  def switch_locale(&action)
    authenticated? # loads the session on pages that don't require one
    I18n.with_locale(requested_locale, &action)
  end

  def requested_locale
    [ current_user&.locale, cookies[:locale], browser_locale ].find { |l| User::LOCALES.include?(l) } || I18n.default_locale
  end

  def browser_locale
    request.env["HTTP_ACCEPT_LANGUAGE"].to_s.scan(/[a-z]{2}/).find { |l| User::LOCALES.include?(l) }
  end
end
