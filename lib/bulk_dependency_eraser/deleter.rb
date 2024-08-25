module BulkDependencyEraser
  class Deleter < Base
    DEFAULT_OPTS = {
      verbose: false,
      db_delete_wrapper: self::DEFAULT_DB_WRAPPER,
    }.freeze

    def initializer class_names_and_ids: {}, opts: {}
      @class_names_and_ids = class_names_and_ids
      super(opts:)
    end



    def execute
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
