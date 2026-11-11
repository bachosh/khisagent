require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice I18n.t("auth.reset_sent")
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice I18n.t("auth.reset_sent")
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice I18n.t("auth.reset_invalid")
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "newpassword", password_confirmation: "newpassword" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice I18n.t("auth.password_reset")
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "newpassword1", password_confirmation: "newpassword2" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice I18n.t("errors.messages.confirmation", attribute: User.human_attribute_name(:password)).first(10)
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
