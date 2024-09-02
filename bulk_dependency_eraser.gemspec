# gem build bulk_dependency_eraser.gemspec

Gem::Specification.new do |s|
  s.name = %q{bulk_dependency_eraser}
  s.version = "1.0.3"
  s.date = %q{2024-08-24}
  s.authors = ["benjamin.dana.software.dev@gmail.com"]
  s.summary = %q{A bulk deletion tool that deletes records and their dependencies without instantiation}
  s.licenses = ['LGPL-3.0-only']
  s.files = [
    "lib/bulk_dependency_eraser.rb",
    "lib/bulk_dependency_eraser/base.rb",
    "lib/bulk_dependency_eraser/builder.rb",
    "lib/bulk_dependency_eraser/deleter.rb",
    "lib/bulk_dependency_eraser/manager.rb",
    "lib/bulk_dependency_eraser/nullifier.rb",
  ]
  s.require_paths = ["lib"]
  s.homepage = 'https://github.com/danabr75/bulk_dependency_eraser'
  s.metadata = { "source_code_uri" => "https://github.com/danabr75/bulk_dependency_eraser" }
  s.add_runtime_dependency 'rails', '>= 6.1'
  s.add_development_dependency 'rails', ['~> 6.1']
  s.add_development_dependency "rspec", ["~> 3.9"]
  s.add_development_dependency "listen", ["~> 3.2"]
  s.add_development_dependency "rspec-rails", ["~> 4.0"]
  s.add_development_dependency "database_cleaner", ["~> 1.8"]
  s.add_development_dependency "sqlite3", ["~> 1.4"]
  s.add_development_dependency "factory_bot", ["~> 6.4"]
  s.add_development_dependency "faker", ["~> 3.4"]
  s.required_ruby_version = '>= 3.1'
end