# frozen_string_literal: true

module CCAccountStatement
  class CSVExtractor
    SUPPORTED_FIELD_SEPARATORS = ["|", ",", "\t", ";"].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filename:, field_separator: "|")
      @filename = filename
      @field_separator = field_separator
    end

    def call
      raise ArgumentError, "filename is required" if missing_value?(filename)
      raise Errno::ENOENT, filename unless File.exist?(filename)

      rows = CSV.read(filename, headers: true, col_sep: resolved_field_separator)
      validate_headers!(rows.headers)

      sections = build_sections(rows)
      Extractor::Result.new(
        filename: filename,
        page_count: nil,
        account_name: nil,
        account_number: nil,
        period_start: nil,
        period_end: nil,
        summary: nil,
        sections: sections
      )
    end

    private

    attr_reader :field_separator, :filename

    def build_sections(rows)
      grouped_sections = {}

      rows.each do |row|
        transaction = build_transaction(row)
        section = (grouped_sections[transaction.section] ||= { total: BigDecimal("0"), transactions: [] })
        section[:total] += transaction.amount
        section[:transactions] << transaction
      end

      grouped_sections.map do |section_name, section_data|
        Extractor::Section.new(
          name: section_name,
          total: section_data[:total],
          transactions: section_data[:transactions]
        )
      end
    end

    def build_transaction(row)
      Extractor::Transaction.new(
        transaction_date: Date.iso8601(row.fetch("transaction_date")),
        posting_date: Date.iso8601(row.fetch("posting_date")),
        section: row.fetch("section"),
        description: row.fetch("description"),
        reference_number: blank_to_nil(row["reference_number"]),
        amount: BigDecimal(row.fetch("amount"))
      )
    end

    def blank_to_nil(value)
      return if value.nil?

      stripped = value.to_s.strip
      stripped.empty? ? nil : stripped
    end

    def resolved_field_separator
      sniffed_field_separator || field_separator
    end

    def sniffed_field_separator
      first_line = File.open(filename, &:readline)

      SUPPORTED_FIELD_SEPARATORS.find do |separator|
        first_line.delete_suffix("\n").delete_suffix("\r").split(separator) == CSVWriter::HEADERS
      end
    rescue EOFError
      nil
    end

    def validate_headers!(headers)
      return if headers == CSVWriter::HEADERS

      raise ArgumentError, "unexpected CSV headers: #{headers.inspect}"
    end

    def missing_value?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
