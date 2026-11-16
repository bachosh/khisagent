# The assistant's "statement analyzed" summary belongs to that statement, so deleting the statement
# (its report and the client data in it) also deletes the summary from the chat.
class AddSummarizedStatementToChatMessages < ActiveRecord::Migration[8.1]
  def up
    add_reference :chat_messages, :summarized_statement, foreign_key: { to_table: :analysis_statements }

    # Link existing summaries: they start with "**<filename>**"
    select_rows("SELECT id, conversation_id, filename FROM analysis_statements").each do |id, conversation_id, filename|
      execute <<~SQL
        UPDATE chat_messages SET summarized_statement_id = #{id.to_i}
        WHERE conversation_id = #{conversation_id.to_i} AND role = 'assistant' AND summarized_statement_id IS NULL
          AND content LIKE #{quote("**#{filename}**%")}
      SQL
    end
  end

  def down
    remove_reference :chat_messages, :summarized_statement, foreign_key: { to_table: :analysis_statements }
  end
end
