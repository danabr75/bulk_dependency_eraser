module BulkDependencyEraser
  class Base
    DEFAULT_OPTS = {test: nil}.freeze

    DEFAULT_DB_WRAPPER = ->(block) { block.call }

    OPTIONS_CONTAINER = Struct.new(
      *DEFAULT_OPTS.keys,
      keyword_init: true
    )

    attr_reader :errors

    def initialize opts: {}
      filtered_opts = opts.slice(*self.class::DEFAULT_OPTS.keys)
      @opts_c = self.class::OPTIONS_CONTAINER.new(
        **self.class::DEFAULT_OPTS.merge(
          filtered_opts
        )
      ).freeze
      @errors = []
    end

    def execute
      raise NotImplementedError
    end

    protected

    def report_error msg
      @errors << msg
    end

    def merge_errors errors, prefix = nil
      local_errors = errors.dup

      unless local_errors.any?
        local_errors << '<NO ERRORS FOUND TO MERGE>'
      end

      if prefix
        local_errors = errors.map { |error| prefix + error }
      end
      @errors += local_errors
    end

    attr_reader :opts_c
  end
end
