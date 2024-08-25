# Used for development testing only!
source 'https://rubygems.org'
ruby '3.2.1'

group :development, :test do
  gem 'rspec', '~> 3.9'
  gem 'rails', '~> 6.1'
  # Needed to test app rails console
  gem 'listen'
  gem 'rspec-rails', '~> 4.0'
  gem 'database_cleaner', '~> 1.8'
  # https://github.com/rails/rails/issues/35153. sqlite3 issue with Rails 5.2.2
  gem 'sqlite3', '~> 1.4'
  # temp here, until in-memory tests work
  # gem 'pg', '0.18.2'
end