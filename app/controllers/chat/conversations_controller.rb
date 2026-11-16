class ConversationsController < ApplicationController
  before_action :set_conversation, only: %i[ show update destroy ]

  def index
    @conversations = current_user.conversations.recent.includes(statements: :risk_report)
    @conversations = @conversations.where("title LIKE ?", "%#{Conversation.sanitize_sql_like(params[:q])}%") if params[:q].present?
  end

  def new
  end

  def create
    submission = Chat::Submission.new(user: current_user, content: params[:content], files: params[:files])
    if submission.call
      redirect_to submission.conversation
    else
      redirect_to new_conversation_path, alert: submission.errors.to_sentence
    end
  end

  def show
    @messages = @conversation.messages.includes(statements: :risk_report)
  end

  def update
    @conversation.update!(title: params.expect(conversation: [ :title ])[:title].to_s.squish.truncate(80))
    redirect_to @conversation, status: :see_other
  end

  def destroy
    @conversation.destroy!
    redirect_to conversations_path, notice: t("conversations.deleted"), status: :see_other
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end
end
