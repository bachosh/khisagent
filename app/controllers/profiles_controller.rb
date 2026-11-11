class ProfilesController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    @user = current_user
    attributes = profile_params
    attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?

    if @user.update(attributes)
      cookies.permanent[:locale] = @user.locale
      redirect_to edit_profile_path, notice: t("profile.saved", locale: @user.locale)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.expect(user: %i[ name company locale password password_confirmation ])
  end
end
