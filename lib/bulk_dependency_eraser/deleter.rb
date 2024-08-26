module BulkDependencyEraser
  class Deleter < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_delete_wrapper: self::DEFAULT_DB_WRAPPER,
    }.freeze

    def initialize class_names_and_ids: {}, opts: {}
      @class_names_and_ids = class_names_and_ids
      super(opts:)
    end

    def execute
      ActiveRecord::Base.transaction do
        current_class_name = 'N/A'
        begin
          class_names_and_ids.keys.reverse.each do |class_name|
            current_class_name = class_name
            ids = class_names_and_ids[class_name]
            klass = class_name.constantize

            # Disable any ActiveRecord::InvalidForeignKey raised errors.
            # src https://stackoverflow.com/questions/41005849/rails-migrations-temporarily-ignore-foreign-key-constraint
            #     https://apidock.com/rails/ActiveRecord/ConnectionAdapters/AbstractAdapter/disable_referential_integrity
            ActiveRecord::Base.connection.disable_referential_integrity do
              delete_in_db do
                klass.unscoped.where(id: ids).delete_all
              end
            end
          end
        rescue Exception => e
          report_error("Issue attempting to delete '#{current_class_name}': #{e.name} - #{e.message}")
          raise ActiveRecord::Rollback
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_and_ids

    def delete_in_db(&block)
      puts "Deleting from DB..." if opts_c.verbose
      opts_c.db_delete_wrapper.call(block)
    end

  end
end
