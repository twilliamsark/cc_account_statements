# frozen_string_literal: true

require "test_helper"

class CCAccountStatementCSVExtractorTest < Minitest::Test
  FakeExtractor = Struct.new(:result) do
    def call(filename:)
      raise ArgumentError, "filename is required" if filename.nil? || filename.to_s.strip.empty?

      result
    end
  end

  def test_requires_a_filename
    error = assert_raises(ArgumentError) do
      CCAccountStatement::CSVExtractor.call(filename: nil)
    end

    assert_match(/filename is required/i, error.message)
  end

  def test_raises_when_the_csv_file_is_missing
    assert_raises(Errno::ENOENT) do
      CCAccountStatement::CSVExtractor.call(filename: "/tmp/missing-cc-statement.csv")
    end
  end

  def test_rebuilds_sections_and_transactions_from_a_pipe_delimited_csv
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cc_transactions.csv")
      File.write(path, <<~CSV)
        transaction_date|posting_date|section|description|reference_number|amount
        2026-07-31|2026-07-31|Payments and Other Credits|PAYMENT FROM SAV 3148|3508|-2643.65
        2026-07-28|2026-07-28|Fees|FOREIGN TRANSACTION FEE|3094|0.93
        2026-08-25|2026-08-25|Interest Charged|INTEREST CHARGED ON PURCHASES||0.00
      CSV

      result = CCAccountStatement::CSVExtractor.call(filename: path)

      assert_equal path, result.filename
      assert_nil result.page_count
      assert_equal ["Payments and Other Credits", "Fees", "Interest Charged"], result.sections.map(&:name)

      payments = result.sections.first
      assert_equal BigDecimal("-2643.65"), payments.total
      assert_equal 1, payments.transactions.size
      assert_equal Date.new(2026, 7, 31), payments.transactions.first.transaction_date
      assert_equal "3508", payments.transactions.first.reference_number

      interest = result.sections.last.transactions.first
      assert_nil interest.reference_number
      assert_equal BigDecimal("0.0"), interest.amount

      assert_equal 3, result.transactions.size
      assert_equal BigDecimal("-2642.72"), result.transactions.sum(&:amount)
    end
  end

  def test_reads_a_csv_with_a_custom_separator
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cc_transactions.csv")
      File.write(path, <<~CSV)
        transaction_date,posting_date,section,description,reference_number,amount
        2026-07-28,2026-07-28,Fees,FOREIGN TRANSACTION FEE,3094,0.93
      CSV

      result = CCAccountStatement::CSVExtractor.call(filename: path, field_separator: ",")

      assert_equal ["Fees"], result.sections.map(&:name)
      assert_equal BigDecimal("0.93"), result.sections.first.total
      assert_equal "FOREIGN TRANSACTION FEE", result.transactions.first.description
    end
  end

  def test_auto_detects_a_comma_separated_csv_when_no_separator_is_passed
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cc_transactions.csv")
      File.write(path, <<~CSV)
        transaction_date,posting_date,section,description,reference_number,amount
        2026-07-28,2026-07-28,Fees,FOREIGN TRANSACTION FEE,3094,0.93
      CSV

      result = CCAccountStatement::CSVExtractor.call(filename: path)

      assert_equal ["Fees"], result.sections.map(&:name)
      assert_equal BigDecimal("0.93"), result.transactions.first.amount
    end
  end

  def test_rejects_csv_files_with_unexpected_headers
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cc_transactions.csv")
      File.write(path, <<~CSV)
        date|section|description|amount
        2026-07-28|Fees|FOREIGN TRANSACTION FEE|0.93
      CSV

      error = assert_raises(ArgumentError) do
        CCAccountStatement::CSVExtractor.call(filename: path)
      end

      assert_match(/unexpected CSV headers/i, error.message)
    end
  end

  def test_round_trips_the_output_generated_by_csv_writer
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      File.write(source_path, "pdf")

      csv_path = CCAccountStatement::CSVWriter.call(
        filename: source_path,
        extractor: FakeExtractor.new(extractor_result)
      )

      result = CCAccountStatement::CSVExtractor.call(filename: csv_path)

      assert_equal extractor_result.transactions, result.transactions
      assert_equal extractor_result.sections.map(&:name), result.sections.map(&:name)
      assert_equal extractor_result.sections.map(&:total), result.sections.map(&:total)
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
