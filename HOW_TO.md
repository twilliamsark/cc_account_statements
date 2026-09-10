# How To Use CCAccountStatement

`CCAccountStatement` parses Bank of America monthly credit card statement PDFs and the CSV files produced from those PDFs.

This guide uses these example paths:

```text
/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf
/Users/todd/Documents/boa/2026/cc_2026-08-25.csv
```

## Setup

Run `bundle install` from this project directory first so Bundler can load the local gem.

Open `irb` with the gem already on the load path:

```bash
bundle exec irb -r cc_account_statement
```

Plain `irb` (without `bundle exec`) will fail with `cannot load such file -- cc_account_statement` because Ruby does not know about this project's `lib/` yet.

From a script in this project, either use Bundler:

```bash
bundle exec ruby your_script.rb
```

```ruby
require "cc_account_statement"
```

Or put `lib` on the load path yourself:

```bash
ruby -Ilib your_script.rb
```

```ruby
require "cc_account_statement"
```

If you installed the gem system-wide (`gem install cc_account_statements-*.gem`), a plain `require "cc_account_statement"` works without Bundler.

## Read A PDF

```ruby
path = "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"

result = CCAccountStatement::Extractor.call(filename: path)
```

The returned `result` is a `CCAccountStatement::Extractor::Result` with these readers:

- `result.filename`
- `result.page_count`
- `result.account_name`
- `result.account_number`
- `result.period_start`
- `result.period_end`
- `result.summary`
- `result.sections`
- `result.transactions`

Example:

```ruby
result.filename
# => "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"

result.page_count
# => 6

result.account_name
# => "Visa Signature®"

result.account_number
# => "4400 6616 0614 5792"

result.period_start
# => #<Date: 2026-07-26>

result.period_end
# => #<Date: 2026-08-25>
```

## Read The Account Summary

`result.summary` returns balances, payment due information, and year-to-date fee/interest totals from the statement.

```ruby
summary = result.summary

summary.previous_balance
# => 0.149168e4

summary.payments_and_credits
# => -0.1159442e5

summary.purchases_and_adjustments
# => 0.1015385e5

summary.fees_charged
# => 0.93e0

summary.interest_charged
# => 0.0

summary.new_balance
# => 0.5204e2

summary.total_credit_line
# => 0.44e5

summary.total_credit_available
# => 0.4394796e5

summary.cash_credit_line
# => 0.75e4

summary.cash_credit_available
# => 0.75e4

summary.statement_closing_date
# => #<Date: 2026-08-25>

summary.days_in_billing_cycle
# => 31

summary.current_payment_due
# => 0.35e2

summary.total_minimum_payment_due
# => 0.35e2

summary.payment_due_date
# => #<Date: 2026-09-22>

summary.fees_ytd
# => 0.93e0

summary.interest_ytd
# => 0.0
```

## Read Sections

`result.sections` returns payments, purchases, fees, and interest sections found in the PDF.

```ruby
result.sections.map(&:name)
# => ["Payments and Other Credits", "Purchases and Adjustments", "Fees", "Interest Charged"]
```

Each section has:

- `name`
- `total`
- `transactions`

Example:

```ruby
payments = result.sections.first

payments.name
# => "Payments and Other Credits"

payments.total
# => -0.1159442e5

payments.transactions.size
# => 5
```

## Read Transactions

There are two ways to access transactions.

### 1. By section

```ruby
purchases = result.sections.find { |section| section.name == "Purchases and Adjustments" }

purchases.transactions.each do |transaction|
  puts [
    transaction.transaction_date,
    transaction.posting_date,
    transaction.description,
    transaction.reference_number,
    transaction.amount.to_s("F")
  ].join(" | ")
end
```

### 2. As one flat list

`result.transactions` flattens all section transactions into one array and preserves the section name on each transaction.

```ruby
result.transactions.first
# => #<data CCAccountStatement::Extractor::Transaction
#      transaction_date=...,
#      posting_date=...,
#      description="...",
#      reference_number="...",
#      amount=...,
#      section="Payments and Other Credits">
```

Example:

```ruby
result.transactions.each do |transaction|
  puts [
    transaction.posting_date,
    transaction.section,
    transaction.description,
    transaction.amount.to_s("F")
  ].join(" | ")
end
```

## Write Transactions To CSV

`CCAccountStatement::CSVWriter` uses `CCAccountStatement::Extractor` internally and writes the flat transaction list to a delimited file.

By default it writes a pipe-delimited file next to the source PDF.

```ruby
path = "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"

output_path = CCAccountStatement::CSVWriter.call(filename: path)

output_path
# => "/Users/todd/Documents/boa/2026/cc_2026-08-25.csv"
```

The output includes these headers:

- `transaction_date`
- `posting_date`
- `section`
- `description`
- `reference_number`
- `amount`

To use a different separator or output path:

```ruby
CCAccountStatement::CSVWriter.call(
  filename: path,
  output_filename: "/Users/todd/Documents/cc_transactions.csv",
  field_separator: ","
)
```

## Read Transactions From CSV

`CCAccountStatement::CSVExtractor` reads a delimited file created by `CCAccountStatement::CSVWriter` and rebuilds the same structured section and transaction result.

It auto-detects the delimiter from the CSV header row for files written by `CCAccountStatement::CSVWriter`. If detection is not enough for a custom file, you can still pass `field_separator` explicitly.

```ruby
path = "/Users/todd/Documents/cc_transactions.csv"

result = CCAccountStatement::CSVExtractor.call(filename: path)

result.sections.map(&:name)
# => ["Payments and Other Credits", "Purchases and Adjustments", "Fees", "Interest Charged"]
```

The returned object is the same `CCAccountStatement::Extractor::Result` shape, so `result.sections` and `result.transactions` work the same way as the PDF extractor. Account metadata and summary fields are `nil` when reading from CSV.

## Error Cases

If `filename` is missing or blank, the extractors raise `ArgumentError`.

```ruby
CCAccountStatement::Extractor.call(filename: nil)
CCAccountStatement::CSVExtractor.call(filename: nil)
```

If the file does not exist, they raise `Errno::ENOENT`.

```ruby
CCAccountStatement::Extractor.call(filename: "/tmp/missing.pdf")
CCAccountStatement::CSVExtractor.call(filename: "/tmp/missing.csv")
```

## One-Shot Script Example

You can run the extractor without opening an interactive console:

```bash
bundle exec ruby -Ilib -r cc_account_statement -e '
path = "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"
result = CCAccountStatement::Extractor.call(filename: path)

puts "File: #{result.filename}"
puts "Account: #{result.account_name}"
puts "Period: #{result.period_start} to #{result.period_end}"
puts "New balance: #{result.summary.new_balance.to_s("F")}"
puts
puts "Sections:"

result.sections.each do |section|
  puts "- #{section.name}: #{section.total.to_s("F")} (#{section.transactions.size} transactions)"
end
'
```
