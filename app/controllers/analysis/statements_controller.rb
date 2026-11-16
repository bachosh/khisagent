module Analysis
  class StatementsController < ApplicationController
    before_action :set_statement, except: :index

    def index
      @statements = current_user.statements.includes(:risk_report, :conversation).order(created_at: :desc)
      @statements = @statements.left_joins(:risk_report).where(risk_report: { risk_level: params[:level] }) if Analysis::RiskReport::LEVELS.include?(params[:level])
      @statements = @statements.where(status: params[:status]) if Analysis::Statement::STATUSES.include?(params[:status])
      if params[:q].present?
        like = "%#{Analysis::Statement.sanitize_sql_like(params[:q])}%"
        @statements = @statements.where("filename LIKE :q OR account_holder LIKE :q OR bank_name LIKE :q", q: like)
      end
    end

    def show
      @report = @statement.risk_report
      @metrics = @report&.metrics.presence || (Analysis::Metrics.new(@statement).to_h if @statement.operations_count.positive?)
      @operations = filtered_operations
    end

    def download
      send_data @statement.file.download, filename: @statement.filename, type: @statement.file.content_type, disposition: :attachment
    end

    def reanalyze
      if !@statement.processing? || @statement.stalled?
        @statement.update!(status: "queued", error: nil, progress: nil)
        Analysis::ProcessingJob.perform_later(@statement)
      end
      redirect_to @statement.conversation, notice: t("statements.reanalyze_started"), status: :see_other
    end

    def destroy
      conversation = @statement.conversation
      @statement.destroy!
      deleted_page = request.referer.to_s.include?(statement_path(@statement))
      redirect_to (deleted_page ? conversation_path(conversation) : request.referer.presence || conversation_path(conversation)),
                  notice: t("statements.deleted"), status: :see_other
    end

    private

    def set_statement
      @statement = current_user.statements.find(params[:id])
    end

    def filtered_operations
      scope = @statement.operations
      scope = scope.where(category_group: params[:group]) if Analysis::BankCodes.groups.include?(params[:group])
      scope = scope.select(&:risky?) if params[:risky] == "1"
      scope
    end
  end
end
