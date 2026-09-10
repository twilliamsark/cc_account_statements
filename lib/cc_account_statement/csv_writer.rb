# frozen_string_literal: true

module CCAccountStatement
  class CSVWriter
    HEADERS = %w[
      transaction_date
      posting_date
      section
      description
      reference_number
      amount
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filename:, output_filename: nil, field_separator: "|", extractor: Extractor)
      @filename = filename
      @output_filename = usable_value?(output_filename) ? output_filename : default_output_filename
      @field_separator = field_separator
      @extractor = extractor
    end

    def call
      result = extractor.call(filename: filename)

      CSV.open(output_filename, "w", col_sep: field_separator, write_headers: true, headers: HEADERS) do |csv|
        result.transactions.each do |transaction|
          csv << [
            transaction.transaction_date.iso8601,
            transaction.posting_date.iso8601,
            transaction.section,
            transaction.description,
            transaction.reference_number,
            transaction.amount.to_s("F")
          ]
        end
      end

      output_filename
    end

    private

    attr_reader :extractor, :field_separator, :filename, :output_filename

    def default_output_filename
      Pathname(filename).sub_ext(".csv").to_s
    end

    def usable_value?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
