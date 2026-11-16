# Analysis domain: uploaded statements, their operations and risk reports (tables analysis_*),
# plus the import / metrics / risk-agent pipeline in app/services/analysis.
# Controllers in app/controllers/analysis, views in app/views/analysis, jobs in app/jobs/analysis.
module Analysis
  def self.table_name_prefix = "analysis_"

  # Routes, params and dom ids stay short: statement_path, params[:statement], "statement_9"
  def self.use_relative_model_naming? = true
end
