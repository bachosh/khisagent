module Analysis
  # Badges and labels for statements, risk reports and categories (used in chat and report views)
  module StatementsHelper
    def risk_badge(level, label: nil)
      return content_tag(:span, t("risk_levels.none"), class: "badge badge--muted") if level.blank?

      content_tag(:span, label || t("risk_levels.#{level}"), class: "badge badge--dot badge--#{level}")
    end

    def statement_status_badge(statement)
      case statement.status
      when "analyzed" then content_tag(:span, t("statements.status.analyzed"), class: "badge badge--success")
      when "failed" then content_tag(:span, t("statements.status.failed"), class: "badge badge--danger")
      else content_tag(:span, safe_join([ tag.span(class: "spinner"), t("statements.status.#{statement.status}") ]), class: "badge badge--processing")
      end
    end

    # "Totals match" check from Analysis::Reconciler: did we read the whole statement correctly?
    def reconciliation_badge(statement)
      status = statement.reconciliation.presence || "unknown"
      icon, css = { "ok" => [ "check-circle", "badge--success" ], "mismatch" => [ "exclamation-triangle", "badge--danger" ] }
                    .fetch(status, [ "information-circle", "badge--muted" ])
      content_tag(:span, safe_join([ svg_icon(icon), t("reconciliation.#{status}") ]), class: "badge #{css}",
                  title: t("reconciliation.#{status}_hint", difference: statement.reconciliation_difference.to_s))
    end

    def recommendation_icon(recommendation)
      { "approve" => "check-circle", "approve_with_conditions" => "shield-check",
        "manual_review" => "eye", "decline" => "hand-raised" }.fetch(recommendation, "information-circle")
    end

    def file_badge(statement_or_kind)
      kind = statement_or_kind.is_a?(Analysis::Statement) ? statement_or_kind.file_kind : statement_or_kind
      ext = statement_or_kind.is_a?(Analysis::Statement) ? File.extname(statement_or_kind.filename).delete(".").first(4) : kind
      content_tag(:span, ext.presence || kind, class: "file-icon file-icon--#{kind}")
    end

    def tool_label(tool_name)
      t("statements.tools.#{tool_name}", default: tool_name.to_s.humanize)
    end

    def group_label(group)
      Analysis::BankCodes.group_label(group)
    end

    def category_label(category)
      t("categories.#{category}", default: category.to_s.humanize)
    end
  end
end
