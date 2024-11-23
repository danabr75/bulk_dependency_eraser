module BulkDependencyEraser
  class Deleter < Base
    DEFAULT_DB_DELETE_ALL_WRAPPER = ->(deleter, block) do
      begin
        block.call
      rescue StandardError => e
        report_error("Issue attempting to delete '#{current_class_name}': #{e.class.name} - #{e.message}")
      end
    end

    DEFAULT_OPTS = {
      verbose: false,
      # Runs once, all deletions occur within it
      # - useful if you wanted to implement a rollback:
      #   - i.e:
          # db_delete_all_wrapper: lambda do |block|
          #   ActiveRecord::Base.transaction do
          #     begin
          #       block.call
          #     rescue StandardError => e
          #       report_error("Issue attempting to delete '#{current_class_name}': #{e.class.name} - #{e.message}")
          #       raise ActiveRecord::Rollback
          #     end
          #   end
          # end
      db_delete_all_wrapper: self::DEFAULT_DB_DELETE_ALL_WRAPPER,
      db_delete_wrapper: self::DEFAULT_DB_WRITE_WRAPPER,
      # Set to true if you want 'ActiveRecord::InvalidForeignKey' errors raised during deletions
      enable_invalid_foreign_key_detection: false,
      disable_batching: false,
      # a general batching size
      batch_size: 300,
      # A specific batching size for this class, overrides the batch_size
      delete_batch_size: nil,
      # A specific batching size for this class, overrides the batch_size
      disable_delete_batching: nil,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - not indexed by klass name. Proc would handle the logic for that.
      # - 3rd, and lowest, priority of scopes
      # - accepts rails query as parameter
      # - return nil if no applicable scope.
      proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 2nd highest priority of scopes
      proc_scopes_per_class_name: {},
      # Applied to deletion queries
      # - 1st priority of scopes
      deletion_proc_scopes_per_class_name: {},
    }.freeze

    def initialize class_names_and_ids: {}, opts: {}
      @class_names_and_ids = class_names_and_ids
      super(opts:)
    end

    def execute
      if opts_c.verbose && opts_c.enable_invalid_foreign_key_detection
        puts "ActiveRecord::Base.connection.disable_referential_integrity - disabled!"
      end

      current_class_name = 'N/A'
      delete_all_in_db do
        class_names_and_ids.keys.reverse.each do |class_name|
          current_class_name = class_name
          ids = class_names_and_ids[class_name].reverse
          klass = constantize(class_name)

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
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_and_ids

    def custom_scope_for_query(query)
      klass = query.klass
      if opts_c.deletion_proc_scopes_per_class_name.key?(klass.name)
        opts_c.deletion_proc_scopes_per_class_name[klass.name].call(query)
      else
        super(query)
      end
    end

    def batch_size
      opts_c.delete_batch_size || opts_c.batch_size
    end

    def batching_disabled?
      opts_c.disable_delete_batching.nil? ? opts_c.disable_batching : opts_c.disable_delete_batching
    end

    def delete_by_klass_and_ids klass, ids
      puts "Deleting #{klass.name}'s IDs: #{ids}" if opts_c.verbose
      query = klass.unscoped
      query = custom_scope_for_query(query)

      if batching_disabled?
        puts "Deleting without batching" if opts_c.verbose
        delete_in_db do
          deletion_result = query.where(id: ids).delete_all
          # Returning the following data in the event that the gem-implementer wants to insert their own db_delete_wrapper proc
          # and have access to these objects in their proc.
            # - query can give them access to the klass and table_name
          [deletion_result, query, ids]
        end
      else
        puts "Deleting with batching" if opts_c.verbose
        ids.each_slice(batch_size) do |ids_subset|
          delete_in_db do
            deletion_result = query.where(id: ids_subset).delete_all
            # Returning the following data in the event that the gem-implementer wants to insert their own db_delete_wrapper proc
            # and have access to these objects in their proc.
            # - query can give them access to the klass and table_name
            [deletion_result, query, ids_subset]
          end
        end
      end
    end

    def delete_in_db(&block)
      puts "Deleting from DB..." if opts_c.verbose
      opts_c.db_delete_wrapper.call(block)
      puts "Deleting from DB complete." if opts_c.verbose
    end

    def delete_all_in_db(&block)
      puts "Deleting all from DB..." if opts_c.verbose
      opts_c.db_delete_all_wrapper.call(self, block)
      puts "Deleting all from DB complete." if opts_c.verbose
    end
  end
end
