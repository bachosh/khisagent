class MessagesController < ApplicationController
  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    submission = Chat::Submission.new(user: current_user, conversation: conversation,
                                      content: params[:content], files: params[:files])

    respond_to do |format|
      if submission.call
        format.turbo_stream { render turbo_stream: turbo_stream.replace("composer", partial: "messages/composer", locals: { conversation: conversation }) }
        format.html { redirect_to conversation }
      else
        format.turbo_stream do
          flash.now[:alert] = submission.errors.to_sentence
          render turbo_stream: turbo_stream.update("flash", partial: "layouts/flash"), status: :unprocessable_entity
        end
        format.html { redirect_to conversation, alert: submission.errors.to_sentence }
      end
    end
  end
end
