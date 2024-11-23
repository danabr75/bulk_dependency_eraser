require_relative 'utils'

module BulkDependencyEraser
  class Base
    POLY_KLASS_NAME = "<POLY>"
    include BulkDependencyEraser::Utils
    extend BulkDependencyEraser::Utils

    # Default Custom Scope for all classes, no effect.
    DEFAULT_SCOPE_WRAPPER = ->(query) { nil }
    # Default Custom Scope for mapped-by-name classes, no effect.
    DEFAULT_KLASS_MAPPED_SCOPE_WRAPPER = ->(query) { query }

    DEFAULT_DB_READ_WRAPPER  = ->(block) {
      begin
        ActiveRecord::Base.connected_to(role: :reading) do
          block.call
        end
      rescue ActiveRecord::ConnectionNotEstablished
        # No role: :reading setup, use regular connection
        block.call
      end
    }
    DEFAULT_DB_WRITE_WRAPPER = ->(block) {
      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          block.call
        end
      rescue ActiveRecord::ConnectionNotEstablished
        # No role: :writing setup, use regular connection
        block.call
      end
    }
    DEFAULT_DB_BLANK_WRAPPER = ->(block) { block.call }

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

    DEPENDENCY_NULLIFY = %i[
      nullify
    ].freeze

    # Abort deletion if assoc dependency value is any of these.
    # - exception if the :force_destroy_restricted option set true
    DEPENDENCY_RESTRICT = %i[
      restrict_with_error
      restrict_with_exception
    ].freeze

    DEPENDENCY_DESTROY = (
      %i[
        destroy
        delete_all
        destroy_async
      ] + self::DEPENDENCY_RESTRICT
    ).freeze

    DEPENDENCY_DESTROY_IGNORE_REFLECTION_TYPES = [
      # Rails 6.1, when a has_and_delongs_to_many <assoc>, dependent: :destroy,
      # will ignore the destroy. Will neither destroy the join table record nor the association record
      # We will do the same, mirror the fuctionality, by ignoring any :dependent options on these types.
      'ActiveRecord::Reflection::HasAndBelongsToManyReflection'
    ].freeze

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

    protected

    def constantize(klass_name)
      # circular dependencies have suffixes, shave them off
      klass_name.sub(/\.\d+$/, '').constantize
    end

    # A dependent assoc may be through another association. Follow the throughs to find the correct assoc to destroy.
    # @return [Symbol] - association's name
    def find_root_association_from_through_assocs klass, association_name
      reflection = klass.reflect_on_association(association_name)
      options = reflection.options
      if options.key?(:through)
        return find_root_association_from_through_assocs(klass, options[:through])
      else
        association_name
      end
    end

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

    def uniqify_errors!
      @errors.uniq!
    end

    attr_reader :opts_c
  end
end
