class StatementsController < ApplicationController
  before_action :set_statement, except: :index

  def index
    @statements = current_user.statements.includes(:risk_report, :conversation).order(created_at: :desc)
    @statements = @statements.left_joins(:risk_report).where(risk_reports: { risk_level: params[:level] }) if RiskReport::LEVELS.include?(params[:level])
    @statements = @statements.where(status: params[:status]) if Statement::STATUSES.include?(params[:status])
    if params[:q].present?
      like = "%#{Statement.sanitize_sql_like(params[:q])}%"
      @statements = @statements.where("filename LIKE :q OR account_holder LIKE :q OR bank_name LIKE :q", q: like)
    end
  end

  def show
    @report = @statement.risk_report
    @metrics = @report&.metrics.presence || (Statements::Metrics.new(@statement).to_h if @statement.operations_count.positive?)
    @operations = filtered_operations
  end

  def download
    send_data @statement.file.download, filename: @statement.filename, type: @statement.file.content_type, disposition: :attachment
  end

  def reanalyze
    if !@statement.processing? || @statement.stalled?
      @statement.update!(status: "queued", error: nil, progress: nil)
      StatementProcessingJob.perform_later(@statement)
    end
    redirect_to @statement.conversation, notice: t("statements.reanalyze_started"), status: :see_other
  end

  def destroy
    conversation = @statement.conversation
    @statement.destroy!
    redirect_to conversation, notice: t("statements.deleted"), status: :see_other
  end

  private

  def set_statement
    @statement = current_user.statements.find(params[:id])
  end

  def filtered_operations
    scope = @statement.operations
    scope = scope.where(category_group: params[:group]) if Statements::BankCodes.groups.include?(params[:group])
    scope = scope.select(&:risky?) if params[:risky] == "1"
    scope
  end
end
