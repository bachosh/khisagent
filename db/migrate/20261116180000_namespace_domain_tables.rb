# Tables get the prefix of their domain module (Chat::, Analysis::), like khisfari's security_ tables.
class NamespaceDomainTables < ActiveRecord::Migration[8.1]
  RENAMES = {
    conversations: :chat_conversations,
    messages: :chat_messages,
    statements: :analysis_statements,
    operations: :analysis_operations,
    risk_reports: :analysis_risk_reports
  }.freeze

  def change
    RENAMES.each { |from, to| rename_table from, to }

    # Uploaded files are attached by class name
    reversible do |dir|
      dir.up { execute "UPDATE active_storage_attachments SET record_type = 'Analysis::Statement' WHERE record_type = 'Statement'" }
      dir.down { execute "UPDATE active_storage_attachments SET record_type = 'Statement' WHERE record_type = 'Analysis::Statement'" }
    end
  end
end
