class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def home
    redirect_to dashboard_path if authenticated?
  end
end
