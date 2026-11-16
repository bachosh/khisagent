# Chat domain: conversations and messages (tables chat_*).
# Controllers in app/controllers/chat, views in app/views/chat, services in app/services/chat, jobs in app/jobs/chat.
module Chat
  def self.table_name_prefix = "chat_"

  # Routes, params and dom ids stay short: conversation_path, params[:conversation], "message_5"
  def self.use_relative_model_naming? = true
end
