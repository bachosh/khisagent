require "test_helper"

class WorkspaceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "pages require sign in" do
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "landing page and sign up" do
    get root_path
    assert_response :success

    assert_difference -> { User.count } do
      post registration_path, params: { user: { name: "Ana", email_address: "ana@example.ge",
                                                password: "secret123", password_confirmation: "secret123" } }
    end
    assert_redirected_to dashboard_path
  end

  test "uploading a statement starts a chat and queues the analysis" do
    sign_in_as @user
    assert_enqueued_with(job: StatementProcessingJob) do
      post conversations_path, params: { content: "", files: [ fixture_file_upload("sample_statement.csv", "text/csv") ] }
    end
    conversation = @user.conversations.last
    assert_redirected_to conversation_path(conversation)
    assert_equal "sample_statement.csv", conversation.title
    assert_equal 1, conversation.statements.count

    get conversation_path(conversation)
    assert_response :success
  end

  test "a question queues a pending reply" do
    sign_in_as @user
    conversation = @user.conversations.create!
    assert_enqueued_with(job: ChatReplyJob) do
      post conversation_messages_path(conversation), params: { content: "რა შემოსავალი აქვს?" }, as: :turbo_stream
    end
    assert conversation.messages.last.pending?
  end

  test "unsupported files are refused" do
    sign_in_as @user
    post conversations_path, params: { files: [ Rack::Test::UploadedFile.new(file_fixture("sample_statement.csv"), "application/octet-stream", original_filename: "x.exe") ] }
    assert_redirected_to new_conversation_path
    assert_equal 0, @user.statements.count
  end

  test "users cannot see each other's chats and statements" do
    conversation = @other.conversations.create!
    statement = @other.statements.create!(conversation: conversation, filename: "s.csv", file_kind: "csv",
                                          file: { io: file_fixture("sample_statement.csv").open, filename: "s.csv" })
    sign_in_as @user

    get conversation_path(conversation)
    assert_response :not_found
    get statement_path(statement)
    assert_response :not_found
    get download_statement_path(statement)
    assert_response :not_found
  end

  test "all main pages render in both languages" do
    sign_in_as @user
    %w[ ka en ].each do |locale|
      @user.update!(locale: locale)
      [ dashboard_path, conversations_path, new_conversation_path, statements_path, edit_profile_path ].each do |path|
        get path
        assert_response :success, "#{path} (#{locale})"
      end
    end
  end
end
