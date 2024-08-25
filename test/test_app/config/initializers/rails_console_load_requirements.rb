if Rails.const_defined? 'Console'
  puts "Loading Fixtures into Console Environment (call `init` in console)"

  require "rake"
  def init
    TestApp::Application.load_tasks
    ActiveRecord::Base.establish_connection(Rails.env.to_sym)
    ActiveRecord::Schema.verbose = false
    load "#{Rails.root}/db/schema.rb"
    Rake::Task['db:fixtures:load'].reenable
    Rake::Task['db:fixtures:load'].invoke
    puts "FOUND TABLES: #{ActiveRecord::Base.connection.tables.join(', ')}"
  end
end