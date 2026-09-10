# frozen_string_literal: true

module CCAccountStatement
  class Extractor
    Result = Data.define(
      :filename,
      :page_count,
      :account_name,
      :account_number,
      :period_start,
      :period_end,
      :summary,
      :sections
    ) do
      def transactions
        sections.flat_map do |section|
          section.transactions.map do |transaction|
            transaction.with(section: section.name)
          end
        end
      end
    end

    Summary = Data.define(
      :previous_balance,
      :payments_and_credits,
      :purchases_and_adjustments,
      :fees_charged,
      :interest_charged,
      :new_balance,
      :total_credit_line,
      :total_credit_available,
      :cash_credit_line,
      :cash_credit_available,
      :statement_closing_date,
      :days_in_billing_cycle,
      :current_payment_due,
      :total_minimum_payment_due,
      :payment_due_date,
      :fees_ytd,
      :interest_ytd
    )

    Section = Data.define(:name, :total, :transactions)
    Transaction = Data.define(
      :transaction_date,
      :posting_date,
      :description,
      :reference_number,
      :amount,
      :section
    )

    KNOWN_SECTIONS = [
      "Payments and Other Credits",
      "Purchases and Adjustments",
      "Fees",
      "Interest Charged"
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filename:, reader: nil)
      @filename = filename
      @reader = reader
    end

    def call
      raise ArgumentError, "filename is required" if missing_value?(filename)
      raise Errno::ENOENT, filename unless reader || File.exist?(filename)

      pdf = reader || PDF::Reader.new(filename)
      parsed = Parser.new(pdf.pages.map(&:text)).parse

      Result.new(
        filename: filename,
        page_count: pdf.page_count,
        account_name: parsed.fetch(:account_name),
        account_number: parsed.fetch(:account_number),
        period_start: parsed.fetch(:period_start),
        period_end: parsed.fetch(:period_end),
        summary: parsed.fetch(:summary),
        sections: parsed.fetch(:sections)
      )
    end

    private

    attr_reader :filename, :reader

    def missing_value?(value)
      value.nil? || value.to_s.strip.empty?
    end

    class Parser
      PERIOD = /
        \b
        (?<start>[A-Za-z]+\s+\d{1,2})
        \s*-\s*
        (?<end>[A-Za-z]+\s+\d{1,2},\s*\d{4})
        \b
      /x
      ACCOUNT_NUMBER = /Account\s*(?:Number|#)\s*:?\s*(?<number>[\d ]{4,})/i
      ACCOUNT_NAME = /\A(?<name>Visa\s+Signature.?)\s*\z/i
      AMOUNT = /(?<amount>-?\$?[\d,]+\.\d{2}|\$\-[\d,]+\.\d{2})/
      SUMMARY_AMOUNT = /
        \A
        (?<label>.+?)
        \s{2,}
        #{AMOUNT}
      /x
      SUMMARY_DATE = /
        (?<label>Statement\ Closing\ Date|Payment\ Due\ Date)
        \s+
        (?<date>\d{2}\/\d{2}\/\d{4})
      /ix
      DAYS_IN_CYCLE = /\ADays\ in\ Billing\ Cycle\b/i
      DAYS_VALUE = /\A(?<days>\d{1,3})\b/
      TRANSACTION = /
        \A
        (?<transaction_date>\d{2}\/\d{2})
        \s+
        (?<posting_date>\d{2}\/\d{2})
        \s+
        (?<description>.+?)
        (?:
          \s{2,}
          (?<reference>\d{3,})
          \s+
          (?<account>\d{3,4})
        )?
        \s{2,}
        #{AMOUNT}
        \s*
        \z
      /x
      TOTAL = /
        \A
        TOTAL\s+(?<name>.+?)\s+FOR\ THIS\ PERIOD
        \s{2,}
        #{AMOUNT}
        \s*
        \z
      /x
      SECTION_NAME = /\A(?<name>#{Regexp.union(KNOWN_SECTIONS)})\s*\z/
      FEES_YTD = /Total\ fees\ charged\ in\ \d{4}\s+#{AMOUNT}/i
      INTEREST_YTD = /Total\ interest\ charged\ in\ \d{4}\s+#{AMOUNT}/i

      def initialize(pages_text)
        @pages_text = pages_text
        @account_name = nil
        @account_number = nil
        @period_start = nil
        @period_end = nil
        @summary_values = blank_summary
        @sections = []
        @current_section = nil
        @awaiting_days_in_billing_cycle = false
        @in_transactions = false
      end

      def parse
        pages_text.each { |page_text| parse_page(page_text) }
        finalize_section
        {
          account_name: account_name,
          account_number: account_number,
          period_start: period_start,
          period_end: period_end,
          summary: Summary.new(**summary_values),
          sections: sections
        }
      end

      private

      attr_reader :pages_text, :sections, :summary_values
      attr_accessor :account_name, :account_number, :period_start, :period_end,
                    :current_section, :awaiting_days_in_billing_cycle, :in_transactions

      def blank_summary
        {
          previous_balance: nil,
          payments_and_credits: nil,
          purchases_and_adjustments: nil,
          fees_charged: nil,
          interest_charged: nil,
          new_balance: nil,
          total_credit_line: nil,
          total_credit_available: nil,
          cash_credit_line: nil,
          cash_credit_available: nil,
          statement_closing_date: nil,
          days_in_billing_cycle: nil,
          current_payment_due: nil,
          total_minimum_payment_due: nil,
          payment_due_date: nil,
          fees_ytd: nil,
          interest_ytd: nil
        }
      end

      def parse_page(page_text)
        page_text.each_line do |raw_line|
          line = normalize(raw_line)
          next if line.empty?

          capture_metadata(line)
          next if skip?(line)

          if line.match?(/\ATransactions(?:\s+Continued)?\z/i)
            self.in_transactions = true
            next
          end

          if awaiting_days_in_billing_cycle && (match = line.match(DAYS_VALUE))
            summary_values[:days_in_billing_cycle] = Integer(match[:days])
            self.awaiting_days_in_billing_cycle = false
            next
          end

          record_summary_fragments(line)

          if (match = line.match(SECTION_NAME))
            if current_section && current_section[:name] == match[:name]
              next
            end

            start_section(match[:name])
            next
          end

          next unless current_section

          if (match = line.match(TRANSACTION))
            record_transaction(match)
          elsif (match = line.match(TOTAL))
            close_section_with(canonical_section_name(match[:name]), parse_amount(match[:amount]))
          elsif continuation_line?(line)
            append_continuation(line)
          end
        end
      end

      def normalize(raw_line)
        raw_line.to_s.gsub(/\u00a0/, " ").sub(/([A-Za-z])\$/, '\1 $').strip
      end

      def capture_metadata(line)
        if account_name.nil? && (match = line.match(ACCOUNT_NAME))
          self.account_name = collapse_whitespace(match[:name]).sub(/®?\z/, "®")
        end

        if account_number.nil? && (match = line.match(ACCOUNT_NUMBER))
          self.account_number = match[:number].strip.gsub(/\s+/, " ")
        end

        if period_start.nil? && (match = line.match(PERIOD))
          end_date = Date.parse(match[:end])
          start_date = Date.parse("#{match[:start]}, #{end_date.year}")
          start_date = Date.parse("#{match[:start]}, #{end_date.year - 1}") if start_date > end_date
          self.period_start = start_date
          self.period_end = end_date
        end

        if summary_values[:fees_ytd].nil? && (match = line.match(FEES_YTD))
          summary_values[:fees_ytd] = parse_amount(match[:amount])
        end

        if summary_values[:interest_ytd].nil? && (match = line.match(INTEREST_YTD))
          summary_values[:interest_ytd] = parse_amount(match[:amount])
        end
      end

      def record_summary_fragments(line)
        if line.match?(DAYS_IN_CYCLE)
          self.awaiting_days_in_billing_cycle = true
        end

        scan_summary_amounts(line)
        scan_summary_dates(line)
      end

      def scan_summary_amounts(line)
        remaining = line.dup

        while (match = remaining.match(SUMMARY_AMOUNT))
          assign_summary_amount(match[:label].strip, parse_amount(match[:amount]))
          remaining = remaining[match.end(0)..].to_s.strip
          break if remaining.empty?
        end
      end

      def scan_summary_dates(line)
        line.scan(SUMMARY_DATE) do
          match = Regexp.last_match
          assign_summary_date(match[:label].strip, Date.strptime(match[:date], "%m/%d/%Y"))
        end
      end

      def assign_summary_amount(label, amount)
        case label
        when /\APrevious Balance\b/i
          summary_values[:previous_balance] ||= amount
        when /\APayments and Other Credits\z/i
          summary_values[:payments_and_credits] ||= amount
        when /\APurchases and Adjustments\z/i
          summary_values[:purchases_and_adjustments] ||= amount
        when /\AFees Charged\z/i
          summary_values[:fees_charged] ||= amount
        when /\AInterest Charged\z/i
          summary_values[:interest_charged] ||= amount
        when /\ANew Balance Total\z/i
          summary_values[:new_balance] ||= amount
        when /\ATotal Credit Line\z/i
          summary_values[:total_credit_line] ||= amount
        when /\ATotal Credit Available\z/i
          summary_values[:total_credit_available] ||= amount
        when /\ACash Credit Line\z/i
          summary_values[:cash_credit_line] ||= amount
        when /\A(?:Portion of Credit Available\s+)?for Cash\z/i
          summary_values[:cash_credit_available] ||= amount
        when /\ACurrent Payment Due\z/i
          summary_values[:current_payment_due] ||= amount
        when /\ATotal Minimum Payment Due\z/i
          summary_values[:total_minimum_payment_due] ||= amount
        end
      end

      def assign_summary_date(label, date)
        case label
        when /\AStatement Closing Date\b/i
          summary_values[:statement_closing_date] ||= date
        when /\APayment Due Date\b/i
          summary_values[:payment_due_date] ||= date
        end
      end

      def skip?(line)
        line.match?(/\APage \d+ of \d+\z/i) ||
          line.match?(/\ATransaction\s+Posting\b/i) ||
          line.match?(/\ADate\s+Date\s+Description\b/i) ||
          line.match?(/\AIMPORTANT INFORMATION/i) ||
          line.match?(/\AThis page intentionally left blank\z/i) ||
          line.match?(/\Acontinued on next page/i) ||
          line.match?(/\ACustomer Service Information/i) ||
          line.match?(/\AMail billing inquiries to/i) ||
          line.match?(/\AMail payment to/i) ||
          line.match?(/\AInterest Charge Calculation\z/i) ||
          line.match?(/\AYour Annual Percentage Rate/i) ||
          line.match?(/\AImportant Messages\z/i) ||
          line.match?(/\AYour Reward Summary/i) ||
          line.match?(/\AAccount Summary\/Payment Information\b/i) ||
          line.match?(/\A2026 Totals Year-to-Date\z/i) ||
          line.match?(/\ALate Payment Warning:/i) ||
          line.match?(/\ATotal Minimum Payment Warning:/i)
      end

      def start_section(name)
        finalize_section
        self.current_section = { name: name, total: nil, transactions: [] }
      end

      def record_transaction(match)
        current_section[:transactions] << Transaction.new(
          transaction_date: parse_statement_date(match[:transaction_date]),
          posting_date: parse_statement_date(match[:posting_date]),
          description: collapse_whitespace(match[:description]),
          reference_number: match[:reference],
          amount: parse_amount(match[:amount]),
          section: current_section[:name]
        )
      end

      def continuation_line?(line)
        return false if current_section.nil? || current_section[:transactions].empty?
        return false if line.match?(SECTION_NAME) || line.match?(TOTAL) || line.match?(TRANSACTION)
        return false if line.match?(/\ATransactions/i)
        return false if line.match?(/\ATOTAL\b/i)
        return false if line.match?(/Account #/i)
        return false if line.match?(/bankofamerica\.com/i)
        return false if line.match?(/\AType of\b/i)
        return false if line.match?(/\ABalance\b/i)
        return false if line.match?(/\APurchases\s+\d/i)
        return false if line.match?(/\ABase Cash Back/i)
        return false if line.match?(/\ACategory Bonus/i)
        return false if line.match?(/\ARelationship Bonus/i)
        return false if line.match?(/\ACash Back Redeemed/i)
        return false if line.match?(/\ATotal Cash Back/i)
        return false if line.match?(/\ATotal fees charged/i)
        return false if line.match?(/\ATotal interest charged/i)
        return false if line.match?(/\A\d{4} Totals Year-to-Date\z/i)

        true
      end

      def append_continuation(line)
        transaction = current_section[:transactions].last
        current_section[:transactions][-1] = transaction.with(
          description: collapse_whitespace("#{transaction.description} #{line}")
        )
      end

      def close_section_with(name, amount)
        return unless current_section

        current_section[:name] = name if current_section[:name].nil?
        current_section[:total] = amount
        finalize_section
      end

      def finalize_section
        return unless current_section

        current_section[:total] ||= current_section[:transactions].sum(BigDecimal("0"), &:amount)
        sections << Section.new(**current_section)
        self.current_section = nil
      end

      def canonical_section_name(name)
        normalized = collapse_whitespace(name).downcase
        KNOWN_SECTIONS.find { |section| section.downcase == normalized } ||
          KNOWN_SECTIONS.find { |section| normalized.include?(section.downcase) } ||
          collapse_whitespace(name)
      end

      def parse_statement_date(value)
        month, day = value.split("/").map(&:to_i)
        year = period_end&.year || Date.today.year
        date = Date.new(year, month, day)

        if period_start && period_end
          if date > period_end + 45
            date = Date.new(year - 1, month, day)
          elsif date < period_start - 45
            date = Date.new(year + 1, month, day)
          end
        end

        date
      end

      def collapse_whitespace(value)
        value.to_s.gsub(/\s+/, " ").strip
      end

      def parse_amount(value)
        BigDecimal(value.to_s.delete(",").delete("$"))
      end
    end
  end
end
