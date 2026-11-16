class AddReconciliationToAnalysisStatements < ActiveRecord::Migration[8.1]
  def change
    # Result of Analysis::Reconciler: ok | mismatch | unknown, and opening + operations - closing
    add_column :analysis_statements, :reconciliation, :string
    add_column :analysis_statements, :reconciliation_difference, :decimal, precision: 15, scale: 2
  end
end
