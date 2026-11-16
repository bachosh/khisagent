require "test_helper"

class DeletionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @conversation = @user.conversations.create!
    upload = @conversation.messages.create!(role: "user", content: "")
    @statement = @user.statements.create!(conversation: @conversation, message: upload, filename: "s.csv", file_kind: "csv",
                                          file: { io: file_fixture("sample_statement.csv").open, filename: "s.csv" })
    Analysis::Importer.new(@statement).call
    @statement.create_risk_report!(risk_score: 50, risk_level: "medium", recommendation: "manual_review", summary: "x")
    @conversation.messages.create!(role: "assistant", content: "**s.csv** analyzed", summarized_statement: @statement)
    @conversation.messages.create!(role: "user", content: "a question")
  end

  test "deleting an analysis removes the chat, files, operations and reports" do
    sign_in_as @user
    blob_key = @statement.file.blob.key

    perform_enqueued_jobs do
      delete conversation_path(@conversation)
    end
    assert_redirected_to conversations_path

    refute Chat::Conversation.exists?(@conversation.id)
    assert_equal 0, Chat::Message.where(conversation_id: @conversation.id).count
    assert_equal 0, Analysis::Statement.where(id: @statement.id).count
    assert_equal 0, Analysis::Operation.where(statement_id: @statement.id).count
    assert_equal 0, Analysis::RiskReport.where(statement_id: @statement.id).count
    assert_equal 0, ActiveStorage::Blob.where(key: blob_key).count
    refute ActiveStorage::Blob.service.exist?(blob_key)
  end

  test "deleting one report removes its data and its summary, keeps the rest of the chat" do
    sign_in_as @user
    perform_enqueued_jobs do
      delete statement_path(@statement), headers: { "Referer" => statements_url }
    end
    assert_redirected_to statements_url

    assert Chat::Conversation.exists?(@conversation.id)
    assert_equal [ "a question" ], @conversation.messages.reload.map(&:content) # summary + empty upload message gone
    assert_equal 0, Analysis::Operation.where(statement_id: @statement.id).count
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Analysis::Statement", record_id: @statement.id).count
  end

  test "users cannot delete each other's data" do
    sign_in_as users(:two)
    delete conversation_path(@conversation)
    assert_response :not_found
    delete statement_path(@statement)
    assert_response :not_found
    assert Analysis::Statement.exists?(@statement.id)
  end

  test "a job for a statement deleted during analysis stops quietly" do
    running = Analysis::Statement.find(@statement.id) # the job's own copy
    @statement.destroy!

    assert_nothing_raised { Analysis::Processor.call(running) }
    refute Analysis::Statement.exists?(@statement.id)
  end

  test "the delete buttons are on the lists" do
    sign_in_as @user
    get conversations_path
    assert_select "form[action='#{conversation_path(@conversation)}'] input[name='_method'][value='delete']", minimum: 2 # list + sidebar
    get statements_path
    assert_select "form[action='#{statement_path(@statement)}'] input[name='_method'][value='delete']"
  end
end
