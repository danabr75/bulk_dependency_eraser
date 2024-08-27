module BulkDependencyEraser
  class Builder < Base
    DEFAULT_OPTS = {
      force_destroy_restricted: false,
      verbose: false,
      # Some associations scopes take parameters.
      # - We would have to instantiate if we wanted to apply that scope filter.
      instantiate_if_assoc_scope_with_arity: false,
      # wraps around the DB reading
      db_read_wrapper: self::DEFAULT_DB_WRAPPER,
      # Will parse these tables and their dependencies, but will remove the tables from the lists after parsing.
      ignore_tables: [],
      # Won't parse any table in this list
      ignore_tables_and_dependencies: [],
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

    attr_reader :deletion_list, :nullification_list
    attr_reader :ignore_table_deletion_list, :ignore_table_nullification_list

    def initialize query:, opts: {}
      @query = query
      @deletion_list  = {}
      @nullification_list = {}

      # For any ignored table results, they will be stored here
      @ignore_table_deletion_list = {}
      @ignore_table_nullification_list = {}

      super(opts:)

      # populate with klass_names for ignorable klasses
      @ignore_klass_and_dependencies = opts_c.ignore_tables_and_dependencies.collect { |table_name| table_name.classify }
    end

    def execute
      # go through deletion/nullification lists and remove any tables from 'ignore_tables' option
      build_result = build

      # move any klass names if told to ignore them into their respective new lists
      opts_c.ignore_tables.each do |table_name|
        klass_name = table_name.classify
        ignore_table_deletion_list[klass_name]      = deletion_list.delete(klass_name)      if deletion_list.key?(klass_name)
        ignore_table_nullification_list[klass_name] = nullification_list.delete(klass_name) if nullification_list.key?(klass_name)
      end

      return build_result
    end

    def build
      begin
        deletion_query_parser(@query)

        uniqify_errors!

        return errors.none?
      rescue StandardError => e
        if @query.is_a?(ActiveRecord::Relation)
          klass      = @query.klass
          klass_name = @query.klass.name
        else
          # current_query is a normal rails class
          klass      = @query
          klass_name = @query.name
        end
        report_error(
          "
            Error Encountered in 'execute' for '#{klass_name}':
              #{e.class.name}
              #{e.message}
          "
        )

        return false
      end
    end

    def deletion_query_parser query, association_parent = nil
      # necessary for "ActiveRecord::Reflection::ThroughReflection" use-case
      # force_through_destroy_chains = options[:force_destroy_chain] || {}
      # do_not_destroy_self = options[:do_not_destroy] || {}

      if query.is_a?(ActiveRecord::Relation)
        klass      = query.klass
        klass_name = query.klass.name
        table_klass_name = query.klass.table_name.classify
      else
        # current_query is a normal rails class
        klass      = query
        klass_name = query.name
        table_klass_name = query.table_name.classify
      end

      if ignore_klass_and_dependencies.include?(table_klass_name)
        # Not parsing, table and dependencies ignorable
        return
      end

      if opts_c.verbose
        if association_parent
          puts "Building #{klass_name}"
        else
          puts "Building #{association_parent} => #{klass_name}"
        end
      end

      if klass.primary_key != 'id'
        report_error(
          "#{klass_name} - does not use primary_key 'id'. Cannot use this tool to bulk delete."
        )
        return
      end

      # Pluck IDs of the current query
      query_ids = read_from_db do
        query.pluck(:id)
      end

      deletion_list[table_klass_name] ||= []

      # prevent infinite recursion here.
      # - Remove any IDs that have been processed before
      query_ids = query_ids - deletion_list[table_klass_name]
      # If ids are nil, let's find that error
      if query_ids.none? #|| query_ids.nil?
        # quick cleanup, if turns out was an empty class
        deletion_list.delete(table_klass_name) if deletion_list[table_klass_name].none?
        return
      end

      # Use-case: We have more IDs to process
      # - can now safely add to the list, since we've prevented infinite recursion
      deletion_list[table_klass_name] += query_ids

      # Hard to test if not sorted
      # - if we had more advanced rspec matches, we could do away with this.
      deletion_list[table_klass_name].sort! if Rails.env.test?

      # ignore associations that aren't a dependent destroyable type
      destroy_associations = query.reflect_on_all_associations.select do |reflection|
        assoc_dependent_type = reflection.options&.dig(:dependent)&.to_sym
        if DEPENDENCY_DESTROY_IGNORE_REFLECTION_TYPES.include?(reflection.class.name)
          # Ignore those types of associations.
          false
        elsif DEPENDENCY_RESTRICT.include?(assoc_dependent_type) && opts_c.force_destroy_restricted != true
          # If the dependency_type is restricted_with_..., and we're not supposed to destroy those, report errork
          report_error(
            "#{klass_name}'s assoc '#{reflection.name}' has a 'dependent: :#{assoc_dependent_type}' set. " \
            "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
          )
          false
        else
          DEPENDENCY_DESTROY.include?(assoc_dependent_type)
        end
      end

      nullify_associations = query.reflect_on_all_associations.select do |reflection|
        assoc_dependent_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_NULLIFY.include?(assoc_dependent_type)
      end

      destroy_association_names = destroy_associations.map(&:name)
      nullify_association_names = nullify_associations.map(&:name)

      # Iterate through the assoc names, if there are any :through assocs, then remap 
      destroy_association_names = destroy_association_names.collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end
      nullify_association_names = nullify_association_names.collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end

      destroy_association_names.each do |destroy_association_name|
        association_parser(klass, query, query_ids, destroy_association_name, :delete)
      end

      nullify_association_names.each do |nullify_association_name|
        association_parser(klass, query, query_ids, nullify_association_name, :nullify)
      end
    end

    # Iterate through each destroyable association, and recursively call 'deletion_query_parser'.
    def association_parser parent_class, query, query_ids, association_name, type
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name
      assoc_klass = reflection.klass
      assoc_table_klass_name = assoc_klass.table_name.classify

      assoc_query = assoc_klass.unscoped

      unless assoc_klass.primary_key == 'id'
        report_error("#{parent_class.name}'s association '#{association_name}' - assoc class does not use 'id' as a primary_key")
        return
      end

      # If there is an association scope present, check to see how many parameters it's using
      # - if there's any parameter, we have to either skip it or instantiate it to find it's dependencies.
      if reflection.scope&.arity&.nonzero?
        # TODO!
        if opts_c.instantiate_if_assoc_scope_with_arity
          raise "TODO: instantiate and apply scope!"
        else
          report_error(
            "#{parent_class.name} and '#{association_name}' - scope has instance parameters. Use :instantiate_if_assoc_scope_with_arity option?"
          )
          return
        end
      elsif reflection.scope
        # I saw this used somewhere, too bad I didn't save the source for it.
        s = parent_class.reflect_on_association(association_name).scope
        assoc_query = assoc_query.instance_exec(&s)
      end

      specified_primary_key = reflection.options[:primary_key]&.to_s
      specified_foreign_key = reflection.options[:foreign_key]&.to_s

      # handle foreign_key edge cases
      if specified_foreign_key.nil?
        if reflection.options[:polymorphic]
          assoc_query = assoc_query.where({(association_name.singularize + '_type').to_sym => parent_class.table_name.classify})
          specified_foreign_key = association_name.singularize + "_id"
        elsif reflection.options[:as]
          assoc_query = assoc_query.where({(reflection.options[:as].to_s + '_type').to_sym => parent_class.table_name.classify})
          specified_foreign_key = reflection.options[:as].to_s + "_id"
        else
          specified_foreign_key = parent_class.table_name.singularize + "_id"
        end
      end

      # Check to see if foreign_key exists in association class's table
      unless assoc_klass.column_names.include?(specified_foreign_key)
        report_error(
          "
          For #{parent_class.name}'s assoc '#{assoc_klass.name}': Could not determine the assoc's foreign key.
          Generated '#{specified_foreign_key}', but did not exist on the association table.
          "
        )
        return
      end

      # Build association query, based on parent class's primary key and the assoc's foreign key
      # - handle primary key edge cases
      # - The associations might not be using the primary_key of the klass table, but we can support that here.
      if specified_primary_key && specified_primary_key&.to_s != 'id'
        alt_primary_ids = read_from_db do
          query.pluck(specified_primary_key)
        end
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => alt_primary_ids)
      else
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => query_ids)
      end

      if type == :delete
        # Recursively call 'deletion_query_parser' on association query, to delete any if the assoc's dependencies
        deletion_query_parser(assoc_query, parent_class)
      elsif type == :nullify
        # No need for recursion here.
        # - we're not destroying these assocs (just nullifying foreign_key columns) so we don't need to parse their dependencies.
        assoc_ids = read_from_db do
          assoc_query.pluck(:id)
        end

        # No assoc_ids, no need to add it to the nullification list
        return if assoc_ids.none?

        nullification_list[assoc_table_klass_name] ||= {}
        nullification_list[assoc_table_klass_name][specified_foreign_key] ||= []
        nullification_list[assoc_table_klass_name][specified_foreign_key] += assoc_ids
        nullification_list[assoc_table_klass_name][specified_foreign_key].uniq!
      else
        raise "invalid parsing type: #{type}"
      end
    end

    protected

    attr_reader :ignore_klass_and_dependencies

    # A dependent assoc may be through another association. Follow the throughs to find the correct assoc to destroy.
    def find_root_association_from_through_assocs klass, association_name
      reflection = klass.reflect_on_association(association_name)
      options = reflection.options
      if options.key?(:through)
        return find_root_association_from_through_assocs(klass, options[:through])
      else
        association_name
      end
    end

    def read_from_db(&block)
      puts "Reading from DB..." if opts_c.verbose
      opts_c.db_read_wrapper.call(block)
    end
  end
end
