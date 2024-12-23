module BulkDependencyEraser
  class Nullifier < Base
    DEFAULT_DB_NULLIFY_ALL_WRAPPER = ->(nullifier, block) do
      begin
        block.call
      rescue BulkDependencyEraser::Errors::NullifierError => e
        nullifier.report_error(
          <<~STRING.strip
          Issue attempting to nullify klass '#{e.nullifying_klass_name}' on column(s) '#{e.nullifying_columns}'
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
      #     db_nullify_all_wrapper: lambda do |block|
      #       ActiveRecord::Base.transaction do
      #         begin
      #           block.call
      #         rescue StandardError => e
      #           report_error("Issue attempting to nullify '#{current_class_name}': #{e.class.name} - #{e.message}")
      #           raise ActiveRecord::Rollback
      #         end
      #       end
      #     end
      db_nullify_all_wrapper: self::DEFAULT_DB_NULLIFY_ALL_WRAPPER,
      db_nullify_wrapper: self::DEFAULT_DB_WRITE_WRAPPER,
      # Set to true if you want 'ActiveRecord::InvalidForeignKey' errors raised during nullifications
      # - I can't think of a use-case where a nullification would generate an invalid key error
      # - Not hurting anything to leave it in, but might remove it in the future.
      enable_invalid_foreign_key_detection: false,
      disable_batching: false,
      # a general batching size
      batch_size: 300,
      # A specific batching size for this class, overrides the batch_size
      nullify_batch_size: nil,
      # A specific batching size for this class, overrides the batch_size
      disable_nullify_batching: nil,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - not indexed by klass name. Proc would handle the logic for that.
      # - 3rd, and lowest, priority of scopes
      # - accepts rails query as parameter
      # - return nil if no applicable scope.
      proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 2nd highest priority of scopes
      proc_scopes_per_class_name: {},
      # Applied to nullification queries
      # - 1st priority of scopes
      nullification_proc_scopes_per_class_name: {},
    }.freeze

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

      if opts_c.verbose
        puts "Combining nullification column groups (if groupable)"
        puts "Before Combination: #{@class_names_columns_and_ids}"
      end

      @class_names_columns_and_ids = combine_matching_columns(@class_names_columns_and_ids)

      if opts_c.verbose
        puts "After Combination: #{@class_names_columns_and_ids}"
      end
    end

    # Combine columns if the IDs are the same
    # - will do one SQL call instead of several
    def combine_matching_columns(nullification_hash)
      return {} if nullification_hash.none?

      merged_hash = {}

      nullification_hash.each do |klass_name, columns_and_ids|
        merged_hash[klass_name] = {}
        columns_and_ids.each do |key, array|
          sorted_array = array.sort

          # Find any existing key in merged_hash that has the same sorted array
          matching_key = merged_hash[klass_name].keys.find { |k| merged_hash[klass_name][k].sort == sorted_array }

          if matching_key
            # Concatenate the matching keys and update the hash
            new_key = key.is_a?(Array) ? key : [key]
            if matching_key.is_a?(Array)
              new_key += matching_key
            else
              new_key << matching_key
            end

            merged_hash[klass_name][new_key] = sorted_array
            merged_hash[klass_name].delete(matching_key)
          else
            # Otherwise, just add the current key-value pair
            merged_hash[klass_name][key] = sorted_array
          end
        end
      end

      merged_hash
    end

    def execute
      current_class_name = 'N/A'
      current_column = 'N/A'
      nullify_all_in_db do
        begin
        # column_and_ids should have already been reversed in builder
        class_names_columns_and_ids.keys.reverse.each do |class_name|
          current_class_name = class_name
          klass = class_name.constantize
          columns_and_ids = class_names_columns_and_ids[class_name]

          columns_and_ids.each do |column, ids|
            current_column = column
            # Reversing IDs. Last ones in are more likely to be dependencies, and should be deleted first.
            ids = ids.reverse

            if opts_c.enable_invalid_foreign_key_detection
              # nullify with referential integrity
              nullify_by_klass_column_and_ids(klass, column, ids)
            else
              # nullify without referential integrity
              # Disable any ActiveRecord::InvalidForeignKey raised errors.
              # - src: https://stackoverflow.com/questions/41005849/rails-migrations-temporarily-ignore-foreign-key-constraint
              #        https://apidock.com/rails/ActiveRecord/ConnectionAdapters/AbstractAdapter/disable_referential_integrity
              ActiveRecord::Base.connection.disable_referential_integrity do
                nullify_by_klass_column_and_ids(klass, column, ids)
              end
            end
          end
        end
        rescue StandardError => e
          raise BulkDependencyEraser::Errors::NullifierError.new(
            e.class,
            e.message,
            nullifying_klass_name: current_class_name,
            nullifying_columns: current_column.to_s # could be an array, string, or symbol
          )
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_columns_and_ids

    def custom_scope_for_query(query)
      klass = query.klass
      if opts_c.nullification_proc_scopes_per_class_name.key?(klass.name)
        opts_c.nullification_proc_scopes_per_class_name[klass.name].call(query)
      else
        super(query)
      end
    end

    def batch_size
      opts_c.nullify_batch_size || opts_c.batch_size
    end

    def batching_disabled?
      opts_c.disable_nullify_batching.nil? ? opts_c.disable_batching : opts_c.disable_nullify_batching
    end

    # @param klass   [ActiveRecord::Base]
    # @param columns [Symbol | String | Array<String | Symbol>]
    # @param ids     [Array[String | Integer]]
    def nullify_by_klass_column_and_ids klass, columns, ids
      query = klass.unscoped
      query = custom_scope_for_query(query)

      nullify_columns = {}
      # supporting nullification of groups of columns simultaneously
      if columns.is_a?(Array)
        columns.each do |column|
          nullify_columns[column] = nil
        end
      else
        nullify_columns[columns] = nil
      end

      if batching_disabled?
        nullify_in_db do
          nullification_result = query.where(id: ids).update_all(nullify_columns)
          # Returning the following data in the event that the gem-implementer wants to insert their own db_nullify_wrapper proc
          # and have access to these objects in their proc.
          # - query can give them access to the klass and table_name
          [nullification_result, query, ids, nullify_columns]
        end
      else
        ids.each_slice(batch_size) do |ids_subset|
          nullify_in_db do
            nullification_result = query.where(id: ids_subset).update_all(nullify_columns)
            # Returning the following data in the event that the gem-implementer wants to insert their own db_nullify_wrapper proc
            # and have access to these objects in their proc.
            # - query can give them access to the klass and table_name
            [nullification_result, query, ids_subset, nullify_columns]
          end
        end
      end
    end

    def nullify_in_db(&block)
      puts "Nullifying from DB..." if opts_c.verbose
      opts_c.db_nullify_wrapper.call(block)
      puts "Nullifying from DB complete." if opts_c.verbose
    end

    def nullify_all_in_db(&block)
      puts "Nullifying all from DB..." if opts_c.verbose
      opts_c.db_nullify_all_wrapper.call(self, block)
      puts "Nullifying all from DB complete." if opts_c.verbose
    end

  end
end
