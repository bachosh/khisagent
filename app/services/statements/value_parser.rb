module Statements
  # Turns spreadsheet / PDF cell values into Dates and BigDecimals.
  # Bank exports mix formats: "03.01.2026", "2026-01-03 14:22", Excel serial numbers,
  # "1 234,56", "1,234.56", "(300.00)", "-300.00 GEL".
  module ValueParser
    module_function

    EXCEL_EPOCH = Date.new(1899, 12, 30)

    def date(value)
      case value
      when Date then value.to_date
      when Time, DateTime then value.to_date
      when Numeric
        value.between?(20_000, 80_000) ? EXCEL_EPOCH + value.to_i : nil
      when String then date_from_string(value.strip)
      end
    end

    def date_from_string(text)
      return if text.blank?

      if (m = text.match(/\A(\d{4})[-.\/](\d{1,2})[-.\/](\d{1,2})/))
        build_date(m[1], m[2], m[3])
      elsif (m = text.match(/\A(\d{1,2})[-.\/](\d{1,2})[-.\/](\d{2,4})/))
        year = m[3].length == 2 ? "20#{m[3]}" : m[3]
        # Day first (Georgian / European); fall back to month first when the day is > 12
        build_date(year, m[2], m[1]) || build_date(year, m[1], m[2])
      elsif text.match?(/\A\d{5}(\.\d+)?\z/)
        date(text.to_f)
      end
    end

    def build_date(year, month, day)
      Date.new(year.to_i, month.to_i, day.to_i)
    rescue Date::Error
      nil
    end

    def amount(value)
      case value
      when nil then nil
      when Numeric then BigDecimal(value.to_s).round(2)
      when String then amount_from_string(value)
      end
    end

    def amount_from_string(text)
      clean = text.strip
      return if clean.blank?

      negative = clean.start_with?("-", "−") || clean.match?(/\A\(.*\)\z/) || clean.end_with?("-")
      digits = clean.gsub(/[^\d.,]/, "")
      return if digits.blank? || !digits.match?(/\d/)

      digits = normalize_separators(digits)
      number = BigDecimal(digits).round(2)
      negative ? -number : number
    rescue ArgumentError
      nil
    end

    # "1.234,56" -> "1234.56", "1,234.56" -> "1234.56", "1234,5" -> "1234.5"
    def normalize_separators(digits)
      last_dot = digits.rindex(".")
      last_comma = digits.rindex(",")

      if last_dot && last_comma
        decimal = last_dot > last_comma ? "." : ","
        thousands = decimal == "." ? "," : "."
        digits.delete(thousands).tr(",", ".")
      elsif last_comma
        # One comma followed by 1-2 digits is a decimal separator; otherwise thousands
        digits.count(",") == 1 && digits.match?(/,\d{1,2}\z/) ? digits.tr(",", ".") : digits.delete(",")
      elsif last_dot && digits.count(".") > 1
        digits.delete(".")
      else
        digits
      end
    end

    def text(value)
      case value
      when nil then ""
      when Float then value == value.to_i ? value.to_i.to_s : value.to_s
      else value.to_s.squish
      end
    end
  end
end
