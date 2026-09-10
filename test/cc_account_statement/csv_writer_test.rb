# frozen_string_literal: true

require "test_helper"

class CCAccountStatementCSVWriterTest < Minitest::Test
  FakeExtractor = Struct.new(:result) do
    def call(filename:)
      raise ArgumentError, "filename is required" if filename.nil? || filename.to_s.strip.empty?

      result
    end
  end

  def test_writes_transactions_to_a_pipe_delimited_csv_next_to_the_source_file_by_default
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      File.write(source_path, "pdf")

      output_path = CCAccountStatement::CSVWriter.call(
        filename: source_path,
        extractor: FakeExtractor.new(extractor_result)
      )

      assert_equal File.join(dir, "statement.csv"), output_path
      assert_equal <<~CSV, File.read(output_path)
        transaction_date|posting_date|section|description|reference_number|amount
        2026-07-31|2026-07-31|Payments and Other Credits|PAYMENT FROM SAV 3148 CONF#M07249449916|3508|-2643.65
        2026-07-28|2026-07-28|Fees|FOREIGN TRANSACTION FEE|3094|0.93
      CSV
    end
  end

  def test_writes_transactions_using_a_custom_separator_and_output_path
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      output_path = File.join(dir, "transactions.txt")
      File.write(source_path, "pdf")

      returned_path = CCAccountStatement::CSVWriter.call(
        filename: source_path,
        output_filename: output_path,
        field_separator: ",",
        extractor: FakeExtractor.new(extractor_result)
      )

      assert_equal output_path, returned_path
      assert_equal <<~CSV, File.read(output_path)
        transaction_date,posting_date,section,description,reference_number,amount
        2026-07-31,2026-07-31,Payments and Other Credits,PAYMENT FROM SAV 3148 CONF#M07249449916,3508,-2643.65
        2026-07-28,2026-07-28,Fees,FOREIGN TRANSACTION FEE,3094,0.93
      CSV
    end
  end

  private

  def extractor_result
    CCAccountStatement::Extractor::Result.new(
      filename: "/tmp/statement.pdf",
      page_count: 1,
      account_name: "Visa Signature®",
      account_number: "4400 6616 0614 5792",
      period_start: Date.new(2026, 7, 26),
      period_end: Date.new(2026, 8, 25),
      summary: nil,
      sections: [
        CCAccountStatement::Extractor::Section.new(
          name: "Payments and Other Credits",
          total: BigDecimal("-2643.65"),
          transactions: [
            CCAccountStatement::Extractor::Transaction.new(
              transaction_date: Date.new(2026, 7, 31),
              posting_date: Date.new(2026, 7, 31),
              description: "PAYMENT FROM SAV 3148 CONF#M07249449916",
              reference_number: "3508",
              amount: BigDecimal("-2643.65"),
              section: "Payments and Other Credits"
            )
          ]
        ),
        CCAccountStatement::Extractor::Section.new(
          name: "Fees",
          total: BigDecimal("0.93"),
          transactions: [
            CCAccountStatement::Extractor::Transaction.new(
              transaction_date: Date.new(2026, 7, 28),
              posting_date: Date.new(2026, 7, 28),
              description: "FOREIGN TRANSACTION FEE",
              reference_number: "3094",
              amount: BigDecimal("0.93"),
              section: "Fees"
            )
          ]
        )
      ]
    )
  end
end
