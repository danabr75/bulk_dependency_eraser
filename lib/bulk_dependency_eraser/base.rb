module BulkDependencyEraser
  class Base
    # Default Custom Scope for all classes, no effect.
    DEFAULT_SCOPE_WRAPPER = ->(query) { nil }
    # Default Custom Scope for mapped-by-name classes, no effect.
    DEFAULT_KLASS_MAPPED_SCOPE_WRAPPER = ->(query) { query }

    DEFAULT_OPTS = {
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - not indexed by klass name. Proc would handle the logic for that.
      # - 3rd, and lowest, priority of scopes
      # - accepts rails query as parameter
      # - return nil if no applicable scope.
      proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 2nd highest priority of scopes
      proc_scopes_per_class_name: {},
    }.freeze


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

    def custom_scope_for_query(query)
      klass = query.klass
      if opts_c.proc_scopes_per_class_name.key?(klass.name)
        opts_c.proc_scopes_per_class_name[klass.name].call(query)
      else
        # See if non-class-mapped proc returns a value
        non_class_name_mapped_query = opts_c.proc_scopes.call(query)
        if !non_class_name_mapped_query.nil?
          return non_class_name_mapped_query
        else
          # No custom wrapper, return non-effect default
          return self.class::DEFAULT_KLASS_MAPPED_SCOPE_WRAPPER.call(query)
        end
      end
    end

    # Create options container
    def options_container
      Struct.new(
        *self.class::DEFAULT_OPTS.keys,
        keyword_init: true
      ).freeze
    end

    def report_error msg
      # remove new lines, surrounding white space, replace with semicolon delimiters
      n = msg.strip.gsub(/\s*\n\s*/, ' ')
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
