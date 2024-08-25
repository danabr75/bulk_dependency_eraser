module BulkDependencyEraser
  class Nullifier < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_nullify_wrapper: self::DEFAULT_DB_WRAPPER
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
    end

    def execute
      return errors.none?
    end

    protected

    attr_reader :class_names_columns_and_ids

    def delete_in_db(&block)
      puts "Nullifying from DB..." if opts_c.verbose
      opts_c.db_nullify_wrapper.call(block)
    end

  end
end
