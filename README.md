# CCAccountStatement

`CCAccountStatement` parses Bank of America monthly credit card statement PDFs and CSV exports into a structured Ruby result.

The gem provides:

- `CCAccountStatement::Extractor` for PDFs
- `CCAccountStatement::CSVWriter` for writing flat transaction CSV files
- `CCAccountStatement::CSVExtractor` for rebuilding structured results from CSV files

## Installation

Add the gem to your application:

```ruby
gem "cc_account_statements", path: "/path/to/cc_account_statements"
```

Or install it directly after building:

```bash
gem build cc_account_statements.gemspec
gem install cc_account_statements-0.1.0.gem
```

## Quick Start

```ruby
require "cc_account_statement"

result = CCAccountStatement::Extractor.call(
  filename: "/Users/todd/Documents/boa/2026/cc_2026-08-25.pdf"
)

puts result.account_name
puts result.summary.new_balance
puts result.transactions.size
```

Detailed usage examples are in `HOW_TO.md`.
