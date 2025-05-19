module BulkDependencyEraser
  class Deleter < Base
    DEFAULT_DB_DELETE_ALL_WRAPPER = ->(deleter, block) do
      begin
        block.call
      rescue BulkDependencyEraser::Errors::DeleterError => e
        deleter.report_error(
          <<~STRING.strip
          Issue attempting to delete klass '#{e.deleting_klass_name}'
            => #{e.original_error_klass.name}: #{e.message}
          STRING
        )
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
      # - 4th, and lowest, priority of scopes
      # - accepts rails query as parameter
      # - return nil if no applicable scope.
      proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 3rd highest priority of scopes
      proc_scopes_per_class_name: {},
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 2nd highest priority of scopes
      deletion_proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to deletion queries
      # - 1st priority of scopes
      deletion_proc_scopes_per_class_name: {},
      use_ctid_over_primary_key: false,
      # Using PG system column CTID can result in a 10x deletion speed increase
      # - is used in combination with the primary key column to ensure CTID hasn't changed.
      use_pg_system_column_ctid: false,
      delete_ctids_by_partions: false,
    }.freeze

    def initialize class_names_and_ids: {}, additional_identifiers_by_id: {}, opts: {}
      @class_names_and_ids = class_names_and_ids
      @additional_identifiers_by_id = additional_identifiers_by_id || {}
      super(opts:)
    end

    def execute
      if opts_c.verbose && opts_c.enable_invalid_foreign_key_detection
        puts "ActiveRecord::Base.connection.disable_referential_integrity - disabled!"
      end

      current_class_name = 'N/A'
      delete_all_in_db do
        begin
          class_names_and_ids.keys.reverse.each do |class_name|
            current_class_name = class_name
            additional_identifiers = additional_identifiers_by_id[class_name]
            # We have to give implementers the ability to make changes to these lists. Even a full clear.
            # raise "invalid state! #{class_name} not found in 'additional_identifiers_by_id' list" if additional_identifiers.nil?

            # Last in, First out
            ids = class_names_and_ids[class_name].reverse
            klass = constantize(class_name)

            if opts_c.enable_invalid_foreign_key_detection
              # delete with referential integrity
              delete_by_klass_and_ids(klass, ids, additional_identifiers:)
            else
              # delete without referential integrity
              # Disable any ActiveRecord::InvalidForeignKey raised errors.
              # - src: https://stackoverflow.com/questions/41005849/rails-migrations-temporarily-ignore-foreign-key-constraint
              #        https://apidock.com/rails/ActiveRecord/ConnectionAdapters/AbstractAdapter/disable_referential_integrity
              ActiveRecord::Base.connection.disable_referential_integrity do
                delete_by_klass_and_ids(klass, ids, additional_identifiers:)
              end
            end
          end
        rescue StandardError => e
          raise BulkDependencyEraser::Errors::DeleterError.new(e.class, e.message, deleting_klass_name: current_class_name)
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_and_ids, :additional_identifiers_by_id

    def custom_scope_for_query(query)
      klass = query.klass

      if opts_c.deletion_proc_scopes_per_class_name.key?(klass.name)
        result = opts_c.deletion_proc_scopes_per_class_name[klass.name].call(query)
        return result unless result.nil?
      end

      if opts_c.deletion_proc_scopes
        result = opts_c.deletion_proc_scopes.call(query)
        return result unless result.nil?
      end

      return super(query)
    end

    def batch_size
      opts_c.delete_batch_size || opts_c.batch_size
    end

    def batching_disabled?
      opts_c.disable_delete_batching.nil? ? opts_c.disable_batching : opts_c.disable_delete_batching
    end

    # @param additional_identifiers [Hash] can be nil, if chosen to be so by implementers
    # - Key: <ID> (primary_key)
    # - Val: Hash of column/value pairings
    def delete_by_klass_and_ids(klass, ids, additional_identifiers:)
      puts "Deleting #{klass.name}'s IDs: #{ids}" if opts_c.verbose
      query = klass.unscoped
      query = custom_scope_for_query(query)

      # Get column-names/keys of any additional identifer columns
      detected_additional_identifier_columns = additional_identifiers&.values&.flat_map(&:keys)&.uniq || []

      if opts_c.use_pg_system_column_ctid && opts_c.delete_ctids_by_partions && (detected_additional_identifier_columns & ['ctid', 'tableoid::regclass']).size == 2
        partioned_tables = additional_identifiers.values.pluck('tableoid::regclass').uniq
      end

      if batching_disabled?
        puts "Deleting without batching" if opts_c.verbose
        # Delete by partioned CTIDs
        if opts_c.use_pg_system_column_ctid && opts_c.delete_ctids_by_partions && (detected_additional_identifier_columns & ['ctid', 'tableoid::regclass']).size == 2
          puts "Deleting via CTID and table partitions" if opts_c.verbose
          partioned_tables.each do |table_partition|
            identifiers_by_partition = additional_identifiers.filter { |id, identifiers| identifiers['tableoid::regclass'] == table_partition }
            ctids = identifiers_by_partition.values.pluck('ctid')
            delete_in_db do
              sql = <<~SQL
                DELETE FROM #{table_partition}
                WHERE ctid IN (#{ctids.map { |c| "'#{c}'" }.join(', ')});
              SQL
              # Due to the way we've mocked/aliased the partition table in this gem test, we need to also add the partition name as a where clause.
              if ENV['TEST_GEM_ENV'] == 'bulk_dependency_eraser'
                sql.sub!(/;\s*$/, "") # remove terminating semicolon
                sql << " AND tableoid = '#{table_partition}';"
              end
              deleted_count = klass.connection.delete(sql)
              [deleted_count, sql, identifiers_by_partition.keys, identifiers_by_partition]
            end
          end
        else
          delete_in_db do
            deletion_query = query
            if opts_c.use_ctid_over_primary_key && detected_additional_identifier_columns.include?('ctid')
              # Do nothing, query will be deleted via ctid
            else
              deletion_query = deletion_query.where(id: ids)
            end

            # Apply any additional query identifiers (i.e. :ctid column)
            detected_additional_identifier_columns.each do |column|
              deletion_query = deletion_query.where(column => additional_identifiers.values.pluck(column))
            end

            # Perform Deletion
            deletion_result = deletion_query.delete_all
            # Returning the following data in the event that the gem-implementer wants to insert their own db_delete_wrapper proc
            # and have access to these objects in their proc.
              # - query can give them access to the klass and table_name
            [deletion_result, query, ids, additional_identifiers]
          end
        end
      else
        puts "Deleting with batching" if opts_c.verbose
        if opts_c.use_pg_system_column_ctid && opts_c.delete_ctids_by_partions && (detected_additional_identifier_columns & ['ctid', 'tableoid::regclass']).size == 2
          puts "Deleting via CTID and table partitions" if opts_c.verbose
          partioned_tables.each do |table_partition|
            identifiers_by_partition = additional_identifiers.filter { |id, identifiers| identifiers['tableoid::regclass'] == table_partition }
            ids = identifiers_by_partition.keys
            ids.each_slice(batch_size) do |ids_subset|
              additional_identifiers_subset = identifiers_by_partition.slice(*ids_subset)
              ctids = additional_identifiers_subset.values.pluck('ctid')
              delete_in_db do
                sql = <<~SQL
                  DELETE FROM #{table_partition}
                  WHERE ctid IN (#{ctids.map { |c| "'#{c}'" }.join(', ')});
                SQL

                # Due to the way we've mocked/aliased the partition table in this gem test, we need to also add the partition name as a where clause.
                if ENV['TEST_GEM_ENV'] == 'bulk_dependency_eraser'
                  sql.sub!(/;\s*$/, "") # remove terminating semicolon
                  sql << " AND tableoid = '#{table_partition}';"
                end

                deleted_count = klass.connection.delete(sql)
                [deleted_count, sql, ids_subset, additional_identifiers_subset]
              end
            end
          end
        else
          ids.each_slice(batch_size) do |ids_subset|
            additional_identifiers_subset = additional_identifiers&.slice(*ids_subset)
            # Get column-names/keys of any additional identifer columns
            detected_additional_identifier_columns = additional_identifiers_subset&.values&.flat_map(&:keys)&.uniq || []
            delete_in_db do
              deletion_query = query
              if opts_c.use_ctid_over_primary_key && detected_additional_identifier_columns.include?('ctid')
                # Do nothing, query will be deleted via ctid
              else
                deletion_query = deletion_query.where(id: ids_subset)
              end

              # Apply any additional query identifiers (i.e. :ctid column)
              detected_additional_identifier_columns.each do |column|
                deletion_query = deletion_query.where(column => additional_identifiers_subset.values.pluck(column))
              end

              # Perform Deletion
              deletion_result = deletion_query.delete_all

              # Returning the following data in the event that the gem-implementer wants to insert their own db_delete_wrapper proc
              # and have access to these objects in their proc.
              # - query can give them access to the klass and table_name
              [deletion_result, query, ids_subset, additional_identifiers_subset]
            end
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
