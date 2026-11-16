require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatMessageOrderTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @user = users(:one)
    @conversation = @user.conversations.create!
    @upload = @conversation.messages.create!(role: "user", content: "check this file")
    @statement = @user.statements.create!(conversation: @conversation, message: @upload, filename: "s.csv", file_kind: "csv",
                                          file: { io: file_fixture("sample_statement.csv").open, filename: "s.csv" })
    @reply = @conversation.messages.create!(role: "assistant", content: "answer", status: "done")
    @later = @conversation.messages.create!(role: "user", content: "a later question")
  end

  def summarize! = @conversation.messages.create!(role: "assistant", content: "**s.csv** analyzed", summarized_statement: @statement)

  test "a summary that arrives late is shown right after the message that uploaded the file" do
    broadcasts = capture_turbo_stream_broadcasts(@conversation) { @summary = summarize! }

    assert_equal [ @upload, @summary, @reply, @later ].map(&:id), @conversation.displayed_messages.map(&:id)
    assert_equal "after", broadcasts.first["action"]
    assert_equal "message_#{@upload.id}", broadcasts.first["target"]
  end

  test "new chat messages still go to the end" do
    broadcasts = capture_turbo_stream_broadcasts(@conversation) do
      @conversation.messages.create!(role: "user", content: "newest")
    end
    assert_equal "append", broadcasts.first["action"]
    assert_equal "messages", broadcasts.first["target"]
  end

  test "re-analysis replaces the old summary instead of adding one at the bottom" do
    summarize!
    report = @statement.create_risk_report!(risk_score: 40, risk_level: "medium", recommendation: "manual_review", summary: "x")
    Analysis::Processor.new(@statement).send(:post_summary, report)

    summaries = @conversation.messages.where(summarized_statement: @statement)
    assert_equal 1, summaries.count
    assert_equal @upload.id, @conversation.displayed_messages[0].id
    assert_equal summaries.first.id, @conversation.displayed_messages[1].id
  end
end
