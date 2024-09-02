module BulkDependencyEraser
  class Nullifier < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_nullify_wrapper: self::DEFAULT_DB_WRAPPER,
      # Set to true if you want 'ActiveRecord::InvalidForeignKey' errors raised during nullifications
      # - I can't think of a use-case where a nullification would generate an invalid key error
      # - Not hurting anything to leave it in, but might remove it in the future.
      enable_invalid_foreign_key_detection: false
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
          report_error("Issue attempting to nullify '#{current_class_name}' column '#{current_column}': #{e.class.name} - #{e.message}")
          raise ActiveRecord::Rollback
        end
      end

      return errors.none?
    end

    protected

    attr_reader :class_names_columns_and_ids

    def nullify_by_klass_column_and_ids klass, columns, ids
      nullify_columns = {}

      # supporting nullification of groups of columns simultaneously
      if columns.is_a?(Array)
        columns.each do |column|
          nullify_columns[column] = nil
        end
      else
        nullify_columns[columns] = nil
      end

      nullify_in_db do
        klass.unscoped.where(id: ids).update_all(nullify_columns)
      end
    end

    def nullify_in_db(&block)
      puts "Nullifying from DB..." if opts_c.verbose
      opts_c.db_nullify_wrapper.call(block)
    end

  end
end
