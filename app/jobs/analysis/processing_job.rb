module Analysis
  # Import + risk analysis of one statement (from seconds for a CSV to minutes for a scanned PDF)
  class ProcessingJob < ApplicationJob
    queue_as :default
    discard_on ActiveJob::DeserializationError # deleted before the job started

    def perform(statement)
      Analysis::Processor.call(statement)
    end
  end
end
