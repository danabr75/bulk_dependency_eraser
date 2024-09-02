module BulkDependencyEraser
  class Nullifier < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_nullify_wrapper: self::DEFAULT_DB_WRAPPER
    }.freeze

    DEFAULT_DB_WRAPPER = ->(block) do
      ActiveRecord::Base.connected_to(role: :writing) do
        block.call
      end
    end

    # @param class_names_columns_and_ids [Hash] - model names with columns to nullify pointing towards the record IDs that require the nullification.
    # - structure:
    #    {
    #      <model_name>: {
    #        column_name: <array_of_ids>
    #      }
    #    }
    # @param opts [Hash] - hash of options, allowlisted in DEFAULT_OPTS
    def initialize class_names_columns_and_ids:, opts: {}
      @class_names_columns_and_ids = class_names_columns_and_ids
      super(opts:)
    end

    def execute
      ActiveRecord::Base.transaction do
        current_class_name = 'N/A'
        current_column = 'N/A'
        begin
          class_names_columns_and_ids.keys.reverse.each do |class_name|
            current_class_name = class_name
            klass = class_name.constantize

            columns_and_ids = class_names_columns_and_ids[class_name]

            columns_and_ids.each do |column, ids|
              current_column = column
              # Disable any ActiveRecord::InvalidForeignKey raised errors.
              # src https://stackoverflow.com/questions/41005849/rails-migrations-temporarily-ignore-foreign-key-constraint
              #     https://apidock.com/rails/ActiveRecord/ConnectionAdapters/AbstractAdapter/disable_referential_integrity
              ActiveRecord::Base.connection.disable_referential_integrity do
                nullify_in_db do
                  klass.unscoped.where(id: ids).update_all(column => nil)
                end
              end
            end
          end
        rescue StandardError => e
          report_error("Issue attempting to nullify '#{current_class_name}' column '#{current_column}': #{e.class.name} - #{e.message}")
          raise ActiveRecord::Rollback
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_columns_and_ids

    def nullify_in_db(&block)
      puts "Nullifying from DB..." if opts_c.verbose
      opts_c.db_nullify_wrapper.call(block)
    end

  end
end
