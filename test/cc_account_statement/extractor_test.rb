# frozen_string_literal: true

require "test_helper"

class CCAccountStatementExtractorTest < Minitest::Test
  FakePage = Struct.new(:text)
  FakeReader = Struct.new(:page_count, :pages)

  SAMPLE_PAGES = [
    <<~PAGE,
      P.O. BOX 15284                                                                                         Bank of America
      WILMINGTON, DE 19850

        TODD G WILLIAMS

        42 COUNTY ROAD 7276
        JONESBORO AR 72405-0600

                                                                                                                               Visa Signature®

                                                                                                                  Account# 4400 6616 0614 5792
                                                                                                                         July 26 - August 25, 2026



      Account Summary/Payment Information                               New Balance Total                                                  $52.04
                                                                        Current Payment Due                                                 $35.00
      Previous Balance                                      $1,491.68
      Payments and Other Credits                          -$11,594.42   Total Minimum Payment Due                                           $35.00
      Purchases and Adjustments                            $10,153.85   Payment Due Date                                                09/22/2026

      Fees Charged                                              $0.93
      Interest Charged                                          $0.00

      New Balance Total                                        $52.04   Late Payment Warning: If we do not receive your Total Minimum

      Total Credit Line                                     $44,000.00
      Total Credit Available                               $43,947.96
      Cash Credit Line                                       $7,500.00
      Portion of Credit Available
      for Cash                                               $7,500.00
      Statement Closing Date                               08/25/2026     If you make no additional
      Days in Billing Cycle
                                                               31

                                                                                                                                    Page 1 of 6
    PAGE
    <<~PAGE,
      TODD G WILLIAMS        ! Account # 4400 6616 0614 5792 ! July 26 - August 25, 2026

       IMPORTANT INFORMATION ABOUT THIS ACCOUNT

                                                                                                                                    Page 2 of 6
    PAGE
    <<~PAGE,
      TODD G WILLIAMS   ! Account # 4400 6616 0614 5792 ! July 26 - August 25, 2026

      Transactions
      Transaction Posting                                                                Reference      Account

      Date        Date     Description                                                   Number         Number              Amount          Total

                           Payments and Other Credits
      07/31       07/31    PAYMENT FROM SAV 3148 CONF#M07249449916                        3508           5792             -2,643.65
      08/10       08/10    PAYMENT FROM SAV 3148 CONF#x1jc2hj8y                           3646           5792             -1,243.55
      08/14       08/15    Carnival The Fun Shops 800-7647419 FL                          6148           5792              -299.99
      08/19       08/20    Online payment from BRK 4G48                                   1876           5792               -326.05
      08/24       08/24    PAYMENT FROM SAV 3148 CONF#v192za0o4                           7895           5792             -7,081.18
                               TOTAL PAYMENTS AND OTHER CREDITS FOR THIS PERIOD                                                      -$11,594.42


                           Purchases and Adjustments
      07/24       07/27    DEL SOL RETAIL LLC    SKAGWAY     AK                           2249           5792                 30.45
      07/28       07/28    TST-Bard Banker     Victoria BC                                3094           5792                 31.09
                           43.74 CAD
      07/29       07/30    CARNIVAL SPIRIT S    MIAMI     FL                              0686           5792                875.54
                           ARRIVAL DATE 07/21/26
      08/13       08/15    SOUTHWES    5262190917505800-435-9792 TX                       6806           5792              1,354.20
                           WILLIAMS/TOD 12/04 MEM/MCO RNDTRP MCO/MEM
                           continued on next page...

                                                                                                                                    Page 3 of 6
    PAGE
    <<~PAGE,
      TODD G WILLIAMS   ! Account # 4400 6616 0614 5792 ! July 26 - August 25, 2026

      Transactions Continued
      Transaction Posting                                                               Reference      Account

      Date        Date     Description                                                  Number         Number              Amount          Total

                           Purchases and Adjustments
      08/14       08/15    SAMSCLUB #6377       JONESBORO    AR                           2094           5792                28.25
      08/22       08/24    PAPAYA PAYMENTS       530-459-4757 CA                          6816           5792                 0.75
                              TOTAL PURCHASES AND ADJUSTMENTS FOR THIS PERIOD                                                        $2,320.28


                           Fees
      07/28       07/28    FOREIGN TRANSACTION FEE                                        3094           5792                 0.93
                              TOTAL FEES FOR THIS PERIOD                                                                                  $0.93


                           Interest Charged
      08/25       08/25    INTEREST CHARGED ON PURCHASES                                                                      0.00
      08/25       08/25    INTEREST CHARGED ON BALANCE TRANSFERS                                                              0.00
      08/25       08/25    INTEREST CHARGED ON DIR DEP&CHK CASHADV                                                            0.00
      08/25       08/25    INTEREST CHARGED ON BANK CASH ADVANCES                                                             0.00
                              TOTAL INTEREST CHARGED FOR THIS PERIOD                                                                      $0.00



                                              2026 Totals Year-to-Date

                             Total fees charged in 2026                                $0.93


                             Total interest charged in 2026                            $0.00

                                                                                                                                    Page 4 of 6
    PAGE
    <<~PAGE
      TODD G WILLIAMS   ! Account # 4400 6616 0614 5792 ! July 26 - August 25, 2026

                                                This page intentionally left blank

                                                                                                                                    Page 5 of 6
    PAGE
  ].freeze

  def test_requires_a_settable_filename
    error = assert_raises(ArgumentError) do
      CCAccountStatement::Extractor.call(filename: nil, reader: fake_reader)
    end

    assert_match(/filename is required/i, error.message)
  end

  def test_raises_when_the_pdf_file_is_missing
    assert_raises(Errno::ENOENT) do
      CCAccountStatement::Extractor.call(filename: "/tmp/missing-cc-statement.pdf")
    end
  end

  def test_extracts_account_metadata_summary_and_transactions_from_a_credit_card_statement
    result = extract_sample

    assert_equal "cc_2026-08-25.pdf", result.filename
    assert_equal 5, result.page_count
    assert_equal "Visa Signature®", result.account_name
    assert_equal "4400 6616 0614 5792", result.account_number
    assert_equal Date.new(2026, 7, 26), result.period_start
    assert_equal Date.new(2026, 8, 25), result.period_end

    summary = result.summary
    assert_equal BigDecimal("1491.68"), summary.previous_balance
    assert_equal BigDecimal("-11594.42"), summary.payments_and_credits
    assert_equal BigDecimal("10153.85"), summary.purchases_and_adjustments
    assert_equal BigDecimal("0.93"), summary.fees_charged
    assert_equal BigDecimal("0.0"), summary.interest_charged
    assert_equal BigDecimal("52.04"), summary.new_balance
    assert_equal BigDecimal("44000.00"), summary.total_credit_line
    assert_equal BigDecimal("43947.96"), summary.total_credit_available
    assert_equal BigDecimal("7500.00"), summary.cash_credit_line
    assert_equal BigDecimal("7500.00"), summary.cash_credit_available
    assert_equal Date.new(2026, 8, 25), summary.statement_closing_date
    assert_equal 31, summary.days_in_billing_cycle
    assert_equal BigDecimal("35.00"), summary.current_payment_due
    assert_equal BigDecimal("35.00"), summary.total_minimum_payment_due
    assert_equal Date.new(2026, 9, 22), summary.payment_due_date
    assert_equal BigDecimal("0.93"), summary.fees_ytd
    assert_equal BigDecimal("0.0"), summary.interest_ytd

    assert_equal(
      ["Payments and Other Credits", "Purchases and Adjustments", "Fees", "Interest Charged"],
      result.sections.map(&:name)
    )
    assert_equal BigDecimal("-11594.42"), result.sections[0].total
    assert_equal BigDecimal("2320.28"), result.sections[1].total
    assert_equal BigDecimal("0.93"), result.sections[2].total
    assert_equal BigDecimal("0.0"), result.sections[3].total
  end

  def test_joins_multiline_transaction_descriptions_and_keeps_page_continued_sections_together
    result = extract_sample
    purchases = result.sections.find { |section| section.name == "Purchases and Adjustments" }

    assert_equal 6, purchases.transactions.size

    cad = purchases.transactions.find { |transaction| transaction.description.include?("Bard Banker") }
    assert_equal Date.new(2026, 7, 28), cad.transaction_date
    assert_equal Date.new(2026, 7, 28), cad.posting_date
    assert_equal "TST-Bard Banker Victoria BC 43.74 CAD", cad.description
    assert_equal "3094", cad.reference_number
    assert_equal BigDecimal("31.09"), cad.amount

    southwest = purchases.transactions.find { |transaction| transaction.description.include?("SOUTHWES") }
    assert_equal(
      "SOUTHWES 5262190917505800-435-9792 TX WILLIAMS/TOD 12/04 MEM/MCO RNDTRP MCO/MEM",
      southwest.description
    )

    assert_equal Date.new(2026, 8, 14), purchases.transactions.find { |transaction| transaction.description.include?("SAMSCLUB") }.transaction_date
  end

  def test_returns_a_flat_transaction_list_with_section_names
    result = extract_sample

    assert_equal 16, result.transactions.size
    assert_equal(
      ["Payments and Other Credits", "Purchases and Adjustments", "Fees", "Interest Charged"],
      result.transactions.map(&:section).uniq
    )
  end

  def test_extracts_the_bank_of_america_credit_card_statement_when_the_session_file_is_present
    path = "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"
    skip "Credit card PDF is not available at #{path}" unless File.exist?(path)

    result = CCAccountStatement::Extractor.call(filename: path)

    assert_equal path, result.filename
    assert_equal 6, result.page_count
    assert_equal "Visa Signature®", result.account_name
    assert_equal "4400 6616 0614 5792", result.account_number
    assert_equal Date.new(2026, 7, 26), result.period_start
    assert_equal Date.new(2026, 8, 25), result.period_end
    assert_equal BigDecimal("52.04"), result.summary.new_balance
    assert_equal(
      ["Payments and Other Credits", "Purchases and Adjustments", "Fees", "Interest Charged"],
      result.sections.map(&:name)
    )
    assert_equal 96, result.transactions.size
    assert_equal BigDecimal("-11594.42"), result.summary.payments_and_credits
    assert_equal BigDecimal("10153.85"), result.summary.purchases_and_adjustments
    assert_equal BigDecimal("10153.85"), result.sections.find { |section| section.name == "Purchases and Adjustments" }.total

    cad = result.transactions.find { |transaction| transaction.description.include?("43.74 CAD") }
    assert_equal "TST-Bard Banker Victoria BC 43.74 CAD", cad.description

    expected_new_balance =
      result.summary.previous_balance +
      result.summary.payments_and_credits +
      result.summary.purchases_and_adjustments +
      result.summary.fees_charged +
      result.summary.interest_charged
    assert_in_delta expected_new_balance, result.summary.new_balance, 0.001
  end

  private

  def extract_sample
    CCAccountStatement::Extractor.call(
      filename: "cc_2026-08-25.pdf",
      reader: fake_reader
    )
  end

  def fake_reader
    FakeReader.new(SAMPLE_PAGES.size, SAMPLE_PAGES.map { |text| FakePage.new(text) })
  end
end
