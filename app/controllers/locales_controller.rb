class LocalesController < ApplicationController
  allow_unauthenticated_access

  def update
    locale = params[:locale]
    cookies.permanent[:locale] = locale
    current_user&.update!(locale: locale)
    redirect_back fallback_location: root_path, status: :see_other
  end
end
