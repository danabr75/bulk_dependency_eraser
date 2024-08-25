require 'active_record/fixtures'
require 'yaml'

namespace :db do
  namespace :fixtures do
    desc "Load fixtures into the current environment's database."
    task :load => :environment do
      environment = (ENV['RAILS_ENV'] || 'test').to_s.to_sym
      fixtures_dir = ENV['FIXTURES_DIR'] || 'test/fixtures'
      # ActiveRecord::Base.establish_connection(environment.to_s.to_sym)
      Dir.glob(File.join(fixtures_dir, '*.{yml,csv}')).each do |fixture_file|
        ActiveRecord::FixtureSet.create_fixtures(fixtures_dir, File.basename(fixture_file, '.*'))
      end
    end
  end
end