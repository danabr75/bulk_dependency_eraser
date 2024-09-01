module BulkDependencyEraser
  class Base
    DEFAULT_OPTS = {}.freeze

    # Default Database wrapper, no effect.
    DEFAULT_DB_WRAPPER = ->(block) { block.call }

    attr_reader :errors

    def initialize opts: {}
      filtered_opts = opts.slice(*self.class::DEFAULT_OPTS.keys)
      @opts_c = options_container.new(
        self.class::DEFAULT_OPTS.merge(filtered_opts)
      )
      @errors = []
    end

    def execute
      raise NotImplementedError
    end

    protected

    # Create options container
    def options_container
      Struct.new(
        *self.class::DEFAULT_OPTS.keys,
        keyword_init: true
      ).freeze
    end

    def report_error msg
      # remove new lines, surrounding white space, replace with semicolon delimiters
      n = msg.strip.gsub(/\s*\n\s*/, '; ')
      @errors << n
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

    def uniqify_errors!
      @errors.uniq!
    end

    attr_reader :opts_c
  end
end
