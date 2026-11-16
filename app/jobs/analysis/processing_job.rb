# Import + risk analysis of one statement (from seconds for a CSV to minutes for a scanned PDF)
class StatementProcessingJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(statement)
    Statements::Processor.call(statement)
  end
end
