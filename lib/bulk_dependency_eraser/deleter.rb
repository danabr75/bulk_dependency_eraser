module BulkDependencyEraser
  class Deleter < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_delete_wrapper: self::DEFAULT_DB_WRAPPER,
      # Set to true if you want 'ActiveRecord::InvalidForeignKey' errors raised during deletions
      enable_invalid_foreign_key_detection: false,
      disable_batching: false,
      # a general batching size
      batch_size: 300,
      # A specific batching size for this class, overrides the batch_size
      delete_batch_size: nil,
      # A specific batching size for this class, overrides the batch_size
      disable_delete_batching: nil,
    }.freeze

    DEFAULT_DB_WRAPPER = ->(block) do
      ActiveRecord::Base.connected_to(role: :writing) do
        block.call
      end
    end

    def initialize class_names_and_ids: {}, opts: {}
      @class_names_and_ids = class_names_and_ids
      super(opts:)
    end

    def execute
      if opts_c.verbose && opts_c.enable_invalid_foreign_key_detection
        puts "ActiveRecord::Base.connection.disable_referential_integrity - disabled!"
      end

      ActiveRecord::Base.transaction do
        current_class_name = 'N/A'
        begin
          # IDs should have already been reversed in builder
          class_names_and_ids.keys.reverse.each do |class_name|
            current_class_name = class_name
            ids = class_names_and_ids[class_name]
            klass = class_name.constantize

            if opts_c.enable_invalid_foreign_key_detection
              # delete with referential integrity
              delete_by_klass_and_ids(klass, ids)
            else
              # delete without referential integrity
              # Disable any ActiveRecord::InvalidForeignKey raised errors.
              # - src: https://stackoverflow.com/questions/41005849/rails-migrations-temporarily-ignore-foreign-key-constraint
              #        https://apidock.com/rails/ActiveRecord/ConnectionAdapters/AbstractAdapter/disable_referential_integrity
              ActiveRecord::Base.connection.disable_referential_integrity do
                delete_by_klass_and_ids(klass, ids)
              end
            end
          end
        rescue StandardError => e
          report_error("Issue attempting to delete '#{current_class_name}': #{e.class.name} - #{e.message}")
          raise ActiveRecord::Rollback
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_and_ids

    def batch_size
      opts_c.delete_batch_size || opts_c.batch_size
    end

    def batching_disabled?
      opts_c.disable_delete_batching.nil? ? opts_c.disable_batching : opts_c.disable_delete_batching
    end

    def delete_by_klass_and_ids klass, ids
      puts "Deleting #{klass.name}'s IDs: #{ids}" if opts_c.verbose
      if batching_disabled?
        puts "Deleting without batching" if opts_c.verbose
        delete_in_db do
          klass.unscoped.where(id: ids).delete_all
        end
      else
        puts "Deleting with batching" if opts_c.verbose
        ids.each_slice(batch_size) do |ids_subset|
          delete_in_db do
            klass.unscoped.where(id: ids_subset).delete_all
          end
        end
      end
    end

    def delete_in_db(&block)
      puts "Deleting from DB..." if opts_c.verbose
      opts_c.db_delete_wrapper.call(block)
    end
  end
end
