# frozen_string_literal: true

require_relative "lib/cc_account_statement/version"

Gem::Specification.new do |spec|
  spec.name = "cc_account_statements"
  spec.version = CCAccountStatement::VERSION
  spec.authors = ["Todd"]

  spec.summary = "Parse Bank of America credit card statement PDFs and CSV files"
  spec.description = "Extract account summary and transaction data from Bank of America monthly credit card statement PDFs and CSV exports."
  spec.homepage = "https://github.com/twilliamsark/cc_account_statements/blob/main/HOW_TO.md"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "test/**/*_test.rb", "README.md", "HOW_TO.md", "Rakefile"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "csv"
  spec.add_dependency "pdf-reader"

  spec.add_development_dependency "irb"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"

  spec.metadata = {
    "source_code_uri" => "https://github.com/twilliamsark/cc_account_statements",
    "documentation_uri" => "https://github.com/twilliamsark/cc_account_statements/blob/main/HOW_TO.md"
  }
end
