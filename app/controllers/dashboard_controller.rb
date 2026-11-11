class DashboardController < ApplicationController
  def show
    statements = current_user.statements
    reports = RiskReport.joins(:statement).where(statements: { user_id: current_user.id })

    @stats = {
      analyzed: statements.where(status: "analyzed").count,
      processing: statements.where(status: Statement::PROCESSING).count,
      average_score: reports.average(:risk_score)&.round,
      high_risk: reports.where(risk_level: %w[ high critical ]).count,
      operations: statements.sum(:operations_count)
    }
    @level_counts = reports.group(:risk_level).count
    @recent_statements = statements.includes(:risk_report, :conversation).order(created_at: :desc).limit(8)
  end
end
