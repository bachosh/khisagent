module Statements
  # Reference data from config/bank_codes.yml (MCC, ISO 8583 processing codes, stage I groups)
  module BankCodes
    module_function

    def data
      @data ||= YAML.load_file(Rails.root.join("config/bank_codes.yml"), freeze: true)
    end

    def categories
      data["categories"].keys
    end

    def groups
      data["groups"].keys
    end

    def group_for(category)
      data.dig("categories", category, "group") || "unknown"
    end

    def risky?(category)
      data.dig("categories", category, "risky") == true
    end

    def group_label(group, locale = I18n.locale)
      data.dig("groups", group, locale.to_s) || group.to_s.humanize
    end

    # Entry for a 4-digit MCC, including ranges such as "7800-7802"
    def mcc(code)
      code = code.to_s
      return if code.blank?

      data["mcc"][code] || mcc_ranges.find { |range, _| range.cover?(code.to_i) }&.last
    end

    def processing_code(code)
      data["processing_codes"][code.to_s.first(2)] if code.present?
    end

    def indicators
      data["indicators"]
    end

    def warning_trends
      data["warning_trends"]
    end

    def mcc_ranges
      @mcc_ranges ||= data["mcc"].filter_map do |key, entry|
        from, to = key.split("-")
        [ (from.to_i..to.to_i), entry ] if to
      end
    end
  end
end
