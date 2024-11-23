module BulkDependencyEraser
  class Builder < Base
    DEFAULT_OPTS = {
      force_destroy_restricted: false,
      verbose: false,
      # Some associations scopes take parameters.
      # - We would have to instantiate if we wanted to apply that scope filter.
      instantiate_if_assoc_scope_with_arity: false,
      # wraps around the DB reading
      db_read_wrapper: self::DEFAULT_DB_READ_WRAPPER,
      # Will parse these tables and their dependencies, but will remove the tables from the lists after parsing.
      ignore_tables: [],
      # Won't parse any table in this list
      ignore_tables_and_dependencies: [],
      ignore_klass_names_and_dependencies: [],
      disable_batching: false,
      # a general batching size
      batch_size: 10_000,
      # A specific batching size for this class, overrides the batch_size
      read_batch_size: nil,
      # A specific read batching disable option
      disable_read_batching: nil,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - not indexed by klass name. Proc would handle the logic for that.
      # - 3rd, and lowest, priority of scopes
      # - accepts rails query as parameter
      # - return nil if no applicable scope.
      proc_scopes: self::DEFAULT_SCOPE_WRAPPER,
      # Applied to all queries. Useful for taking advantage of specific indexes
      # - 2nd highest priority of scopes
      proc_scopes_per_class_name: {},
      # Applied to reading queries
      # - 1st priority of scopes
      reading_proc_scopes_per_class_name: {},
    }.freeze

    # write access so that these can be edited in-place by end-users who might need to manually adjust deletion order.
    attr_accessor :deletion_list, :nullification_list
    attr_reader :ignore_table_deletion_list, :ignore_table_nullification_list

    def initialize query:, opts: {}
      @query = query
      @deletion_list  = {}
      @nullification_list = {}

      # For any ignored table results, they will be stored here
      @ignore_table_deletion_list = {}
      @ignore_table_nullification_list = {}

      @table_names_to_parsed_klass_names = {}

      super(opts:)

      @ignore_table_name_and_dependencies = opts_c.ignore_tables_and_dependencies.collect { |table_name| table_name }
      @ignore_klass_name_and_dependencies = opts_c.ignore_klass_names_and_dependencies.collect { |klass_name| klass_name }
    end

    def execute
      # go through deletion/nullification lists and remove any tables from 'ignore_tables' option
      build_result = build

      # move any klass names if told to ignore them into their respective new lists
      # - prior approach was to use table_name.classify, but we can't trust that approach.
      opts_c.ignore_tables.each do |table_name|
        table_names_to_parsed_klass_names.dig(table_name)&.each do |klass_name|
          ignore_table_deletion_list[klass_name]      = deletion_list.delete(klass_name)      if deletion_list.key?(klass_name)
          ignore_table_nullification_list[klass_name] = nullification_list.delete(klass_name) if nullification_list.key?(klass_name)
        end
      end

      return build_result
    end

    def build
      begin
        if opts_c.verbose
          puts "Starting build for #{@query.is_a?(ActiveRecord::Relation) ? @query.klass.name : @query.name}"
        end

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
        raise e

        return false
      end
    end

    protected

    attr_reader :ignore_klass_and_dependencies
    attr_reader :table_names_to_parsed_klass_names
    attr_reader :ignore_table_name_and_dependencies, :ignore_klass_name_and_dependencies

    def custom_scope_for_query(query)
      klass = query.klass
      if opts_c.reading_proc_scopes_per_class_name.key?(klass.name)
        opts_c.reading_proc_scopes_per_class_name[klass.name].call(query)
      else
        super(query)
      end
    end

    def pluck_from_query query, column = :id
      # ordering shouldn't matter in these queries, and would slow it down
      # - we're ignoring default_scope ordering, but assoc-defined ordering would still take effect
      query = query.reorder('')
      query = custom_scope_for_query(query)

      query_ids = []
      read_from_db do
        # If the query has a limit, then we don't want to clobber with batching.
        if batching_disabled? || !query.where({}).limit_value.nil?
          # query without batching
          query_ids = query.pluck(column)
        else
          # query with batching
          offset = 0
          loop do
            new_query_ids = query.offset(offset).limit(batch_size).pluck(column)
            query_ids += new_query_ids

            break if new_query_ids.size < batch_size

            # Move to the next batch
            offset += batch_size
          end
        end
      end

      return query_ids
    end

    def batch_size
      opts_c.read_batch_size.nil? ? opts_c.batch_size : opts_c.read_batch_size
    end

    def batching_disabled?
      opts_c.disable_read_batching.nil? ? opts_c.disable_batching : opts_c.disable_read_batching
    end

    def deletion_query_parser query, association_parent = nil
      # necessary for "ActiveRecord::Reflection::ThroughReflection" use-case
      # force_through_destroy_chains = options[:force_destroy_chain] || {}
      # do_not_destroy_self = options[:do_not_destroy] || {}

      if query.is_a?(ActiveRecord::Relation)
        klass      = query.klass
        klass_name = query.klass.name
      else
        # current_query is a normal rails class
        klass      = query
        klass_name = query.name
      end

      table_names_to_parsed_klass_names[klass.table_name] ||= []
      # Need to populate this list here, so we can have access to it later for the :ignore_tables option
      unless table_names_to_parsed_klass_names[klass.table_name].include?(klass_name)
        table_names_to_parsed_klass_names[klass.table_name] << klass_name
      end

      if ignore_table_name_and_dependencies.include?(klass.table_name)
        # Not parsing, table and dependencies ignorable
        return
      end

      if ignore_klass_name_and_dependencies.include?(klass_name)
        # Not parsing, table and dependencies ignorable
        return
      end

      if opts_c.verbose
        if association_parent
          puts "Building #{association_parent}, association of #{klass_name}"
        else
          puts "Building #{klass_name}"
        end
      end

      if klass.primary_key != 'id'
        report_error(
          "#{klass_name} - does not use primary_key 'id'. Cannot use this tool to bulk delete."
        )
        return
      end

      # Pluck IDs of the current query
      query_ids = pluck_from_query(query)

      deletion_list[klass_name] ||= []

      # prevent infinite recursion here.
      # - Remove any IDs that have been processed before
      query_ids = query_ids - deletion_list[klass_name]

      # If ids are nil, let's find that error
      if query_ids.none? #|| query_ids.nil?
        # quick cleanup, if turns out was an empty class
        deletion_list.delete(klass_name) if deletion_list[klass_name].none?
        return
      end

      # Use-case: We have more IDs to process
      # - can now safely add to the list, since we've prevented infinite recursion
      deletion_list[klass_name] += query_ids

      # Hard to test if not sorted
      # - if we had more advanced rspec matches, we could do away with this.
      # deletion_list[klass_name].sort! if Rails.env.test?

      # ignore associations that aren't a dependent destroyable type
      destroy_associations = query.reflect_on_all_associations.select do |reflection|
        assoc_dependent_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_DESTROY.include?(assoc_dependent_type) && !DEPENDENCY_RESTRICT.include?(assoc_dependent_type)
      end

      restricted_associations = query.reflect_on_all_associations.select do |reflection|
        assoc_dependent_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_RESTRICT.include?(assoc_dependent_type)
      end

      nullify_associations = query.reflect_on_all_associations.select do |reflection|
        assoc_dependent_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_NULLIFY.include?(assoc_dependent_type)
      end

      destroy_association_names    = destroy_associations.map(&:name)
      nullify_association_names    = nullify_associations.map(&:name)
      restricted_association_names = restricted_associations.map(&:name)

      # Iterate through the assoc names, if there are any :through assocs, then rename the association
      # - Rails interpretation of any dependencies of a :through association is to apply it to
      #   the leaf association at the end of the :through chain(s)
      destroy_association_names = destroy_association_names.collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end
      nullify_association_names = nullify_association_names.collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end
      restricted_association_names = restricted_association_names.collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end

      if opts_c.verbose
        puts "Destroyable Associations: #{destroy_association_names}"
        puts "Nullifiable Associations: #{nullify_association_names}"
        puts " Restricted Associations: #{restricted_association_names}"
      end

      destroy_association_names.each do |destroy_association_name|
        association_parser(klass, query, query_ids, destroy_association_name, :delete)
      end

      nullify_association_names.each do |nullify_association_name|
        association_parser(klass, query, query_ids, nullify_association_name, :nullify)
      end

      restricted_association_names.each do |restricted_association_name|
        association_parser(klass, query, query_ids, restricted_association_name, :restricted)
      end
    end

    # Used to iterate through each destroyable association, and recursively call 'deletion_query_parser'.
    # @param parent_class     [ApplicationRecord]
    # @param query            [ActiveRecord_Relation] - We need the 'query' in case associations are tied to column other than 'id'
    # @param query_ids        [Array<Int | String>]   - Array of parent's IDs (or UUIDs)
    # @param association_name [Symbol]                - The association name from the parent_class
    # @param type             [Symbol]                - either :delete or :nullify or :restricted
    def association_parser(parent_class, query, query_ids, association_name, type)
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      is_polymorphic = reflection.options[:polymorphic]
      unless is_polymorphic
        klass = reflection.klass

        if ignore_table_name_and_dependencies.include?(klass.table_name)
          # Not parsing, table and dependencies ignorable
          return
        end

        if ignore_klass_name_and_dependencies.include?(klass.name)
          # Not parsing, table and dependencies ignorable
          return
        end

        if self.class::DEPENDENCY_DESTROY_IGNORE_REFLECTION_TYPES.include?(reflection_type)
          report_error("Dependency detected on #{parent_class.name}'s '#{association_name}' - association doesn't support dependency")
          return 
        end
      end

      case reflection_type
      when 'ActiveRecord::Reflection::HasManyReflection'
        association_parser_has_many(parent_class, query, query_ids, association_name, type)
      when 'ActiveRecord::Reflection::HasOneReflection'
        association_parser_has_many(parent_class, query, query_ids, association_name, type)
      when 'ActiveRecord::Reflection::BelongsToReflection'
        if type == :nullify
          report_error("#{parent_class.name}'s association '#{association_name}' - dependent 'nullify' invalid for 'belongs_to'")
        else
          association_parser_belongs_to(parent_class, query, query_ids, association_name, type)
        end
      else
        report_message("Unsupported association type for #{parent_class.name}'s association '#{association_name}': #{reflection_type}")
      end
    end

    # Handles the :has_many association type
    # - handles it's polymorphic associations internally (easier on the has_many)
    def association_parser_has_many(parent_class, query, query_ids, association_name, type, opts = {})
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      assoc_klass = reflection.klass
      assoc_klass_name = assoc_klass.name

      assoc_query = assoc_klass.unscoped

      unless assoc_klass.primary_key == 'id'
        report_error("#{parent_class.name}'s association '#{association_name}' - assoc class does not use 'id' as a primary_key")
        return
      end

      # If there is an association scope present, check to see how many parameters it's using
      # - if there's any parameter, we have to either skip it or instantiate it to find it's dependencies.
      if reflection.scope&.arity&.nonzero?
        if opts_c.instantiate_if_assoc_scope_with_arity
          association_parser_has_many_instantiation(parent_class, query, query_ids, association_name, type, opts)
          return
        else
          report_error(
            "#{parent_class.name} and '#{association_name}' - scope has instance parameters. Use :instantiate_if_assoc_scope_with_arity option?"
          )
          return
        end
      elsif reflection.scope
        # I saw this used somewhere, too bad I didn't save the source for it.
        assoc_scope = parent_class.reflect_on_association(association_name).scope
        assoc_query = assoc_query.instance_exec(&assoc_scope)
      end

      # Look for manually specified keys in the assocation first
      specified_primary_key = reflection.options[:primary_key]&.to_s
      specified_foreign_key = reflection.options[:foreign_key]&.to_s
      # For polymorphic_associations
      specified_foreign_type = nil

      # handle foreign_key edge cases
      if specified_foreign_key.nil?
        if reflection.options[:as]
          specified_foreign_type = "#{reflection.options[:as]}_type"
          specified_foreign_key = "#{reflection.options[:as]}_id"
          # Only filtering by type here, the extra work for a poly assoc. We filter by IDs later
          assoc_query = assoc_query.where({ specified_foreign_type.to_sym => parent_class.name })
        else
          specified_foreign_key = parent_class.table_name.singularize + "_id"
        end
      end

      # Check to see if foreign_key exists in association class's table
      unless assoc_klass.column_names.include?(specified_foreign_key)
        report_error(
          "
          For #{parent_class.name}'s assoc '#{assoc_klass.name}': Could not determine the assoc's foreign key.
          Foreign key should have been '#{specified_foreign_key}', but did not exist on the #{assoc_klass.table_name} table.
          "
        )
        return
      end

      # Build association query, based on parent class's primary key and the assoc's foreign key
      # - handle primary key edge cases
      # - The associations might not be using the primary_key of the klass table, but we can support that here.
      if specified_primary_key && specified_primary_key&.to_s != 'id'
        alt_primary_ids = pluck_from_query(query, specified_primary_key)
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => alt_primary_ids)
      else
        assoc_query = assoc_query.where(specified_foreign_key.to_sym => query_ids)
      end

      # remove any ordering or limits imposed on the association queries from the association definitions
      assoc_query = assoc_query.reorder('').unscope(:limit)

      if type == :delete
        # Recursively call 'deletion_query_parser' on association query, to delete any if the assoc's dependencies
        deletion_query_parser(assoc_query, parent_class)
      elsif type == :restricted
        if traverse_restricted_dependency?(parent_class, reflection, assoc_query)
          deletion_query_parser(assoc_query, parent_class)
        end
      elsif type == :nullify
        # No need for recursion here.
        # - we're not destroying these assocs (just nullifying foreign_key columns) so we don't need to parse their dependencies.
        assoc_ids = pluck_from_query(assoc_query)

        # No assoc_ids, no need to add it to the nullification list
        return if assoc_ids.none?

        nullification_list[assoc_klass_name] ||= {}
        nullification_list[assoc_klass_name][specified_foreign_key] ||= []
        nullification_list[assoc_klass_name][specified_foreign_key] += assoc_ids
        nullification_list[assoc_klass_name][specified_foreign_key].uniq!

        # nullification_list[assoc_klass_name][specified_foreign_key].sort! if Rails.env.test?

        # Also nullify the 'type' field, if the association is polymorphic
        if specified_foreign_type
          nullification_list[assoc_klass_name][specified_foreign_type] ||= []
          nullification_list[assoc_klass_name][specified_foreign_type] += assoc_ids
          nullification_list[assoc_klass_name][specified_foreign_type].uniq!

          # nullification_list[assoc_klass_name][specified_foreign_type].sort! if Rails.env.test?
        end
      else
        raise "invalid parsing type: #{type}"
      end
    end

    # So you've decided to attempt instantiation...
    # This will be a lot slower than the rest of our logic here, but if needs must.
    #
    # This method will replicate association_parser, but instantiate and iterate in batches
    def association_parser_has_many_instantiation(parent_class, query, query_ids, association_name, type, opts)
      raise "Invalid State! Not ready to instantiate!"
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name
      assoc_klass = reflection.klass
      assoc_klass_name = assoc_klass.name


      # specified_primary_key = reflection.options[:primary_key]&.to_s
      # specified_foreign_key = reflection.options[:foreign_key]&.to_s

      # assoc_query = assoc_klass.unscoped
      # query.in_batches

      assoc_klass.in_batches(of: batch_size) do |batch|
        batch.each do |record|
          record.send(association_name)
        end
      end
    end

    def association_parser_belongs_to(parent_class, query, query_ids, association_name, type)
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      # Can't run certain checks on a polymorphic association, no definitive klass to use.
      # - Usually, the polymorphic class is the leaf in a dependency tree.
      # - In this case, i.e.: a `belongs_to :polymorphicable, polymorphic: true, dependent: :destroy` use-case
      if reflection.options[:polymorphic]
        # We'd have to pluck our various types, iterate through each, using each type as the assoc_query starting point
        association_parser_belongs_to_polymorphic(parent_class, query, query_ids, association_name, type)
        return
      end

      assoc_klass = reflection.klass
      assoc_klass_name = assoc_klass.name

      assoc_query = assoc_klass.unscoped

      unless assoc_klass.primary_key == 'id'
        report_error("#{parent_class.name}'s association '#{association_name}' - assoc class does not use 'id' as a primary_key")
        return
      end

      # If there is an association scope present, check to see how many parameters it's using
      # - if there's any parameter, we have to either skip it or instantiate it to find it's dependencies.
      if reflection.scope&.arity&.nonzero?
        # TODO: PENDING:
        # if opts_c.instantiate_if_assoc_scope_with_arity
        #   association_parser_belongs_to_instantiation(parent_class, query, query_ids, association_name, type)
        #   return
        # else
        #   report_error(
        #     "#{parent_class.name} and '#{association_name}' - scope has instance parameters. Use :instantiate_if_assoc_scope_with_arity option?"
        #   )
        #   return
        # end
      elsif reflection.scope
        # I saw this used somewhere, too bad I didn't save the source for it.
        assoc_scope = parent_class.reflect_on_association(association_name).scope
        assoc_query = assoc_query.instance_exec(&assoc_scope)
      end

      specified_primary_key = reflection.options[:primary_key] || 'id'
      specified_foreign_key = reflection.options[:foreign_key] || "#{association_name}_id"

      # Check to see if foreign_key exists in our parent table
      unless parent_class.column_names.include?(specified_foreign_key)
        report_error(
          "
          For #{parent_class.name}'s association '#{association_name}': Could not determine the assoc's foreign key.
          Foreign key should have been '#{specified_foreign_key}', but did not exist on the #{parent_class.table_name} table.
          "
        )
        return
      end

      foreign_keys = pluck_from_query(query, specified_foreign_key)
      assoc_query = assoc_query.where(
        specified_primary_key.to_sym => foreign_keys
      )

      # remove any ordering or limits imposed on the association queries from the association definitions
      assoc_query = assoc_query.reorder('').unscope(:limit)

      if type == :delete
        # Recursively call 'deletion_query_parser' on association query, to delete any if the assoc's dependencies
        deletion_query_parser(assoc_query, parent_class)
      elsif type == :restricted
        if traverse_restricted_dependency?(parent_class, reflection, assoc_query)
          deletion_query_parser(assoc_query, parent_class)
        end
      else
        raise "invalid parsing type: #{type}"
      end
    end

    # So you've decided to attempt instantiation...
    # This will be a lot slower than the rest of our logic here, but if needs must.
    #
    # This method will replicate association_parser, but instantiate and iterate in batches
    def association_parser_belongs_to_instantiation(parent_class, query, query_ids, association_name, type)
      # pending
      raise "Invalid State! Not ready to instantiate!"
    end

    # In this case, it's like a `belongs_to :polymorphicable, polymorphic: true, dependent: :destroy` use-case
    # - it's unusual, but valid use-case
    def association_parser_belongs_to_polymorphic(parent_class, query, query_ids, association_name, type)
      # raise "Unsupported use-case: #{parent_class.name} -> belongs_to :polymorphicable, polymorphic: true, dependent: :destroy"

      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      # If there is an association scope present, check to see how many parameters it's using
      # - if there's any parameter, we have to either skip it or instantiate it to find it's dependencies.
      if reflection.scope&.arity&.nonzero?
        raise 'PENDING'
      elsif reflection.scope
        # I saw this used somewhere, too bad I didn't save the source for it.
        assoc_scope = parent_class.reflect_on_association(association_name).scope
        assoc_query = assoc_query.instance_exec(&assoc_scope)
      end

      specified_primary_key = reflection.options[:primary_key] || 'id'
      specified_foreign_key = reflection.options[:foreign_key] || "#{association_name}_id"
      specified_foreign_type = specified_foreign_key.sub(/_id$/, '_type')

      # Check to see if foreign_key exists in our parent table
      unless parent_class.column_names.include?(specified_foreign_key)
        report_error(
          "
          For #{parent_class.name}'s association '#{association_name}': Could not determine the class's foreign key.
          Foreign key should have been '#{specified_foreign_key}', but did not exist on the #{parent_class.table_name} table.
          "
        )
        return
      end
      unless parent_class.column_names.include?(specified_foreign_type)
        report_error(
          "
          For #{parent_class.name}'s association '#{association_name}': Could not determine the class's polymorphic type.
          Foreign key should have been '#{specified_foreign_type}', but did not exist on the #{parent_class.table_name} table.
          "
        )
        return
      end

      query = custom_scope_for_query(query)

      foreign_ids_by_type = read_from_db do
        if batching_disabled? || !query.where({}).limit_value.nil?
          # query without batching
          query.reorder('').pluck(specified_foreign_key, specified_foreign_type).each_with_object({}) do |(id, type), hash|
            hash.key?(type) ? hash[type] << id : hash[type] = [id]
          end
        else
          columns_and_ids = {}
          offset = 0
          loop do
            counter = 0
            query.reorder('').offset(offset).limit(batch_size).pluck(specified_foreign_key, specified_foreign_type).each do |id, type|
              columns_and_ids.key?(type) ? columns_and_ids[type] << id : columns_and_ids[type] = [id]
              counter += 1
            end

            break if counter < batch_size

            # Move to the next batch
            offset += batch_size
          end
          columns_and_ids
        end
      end

      if type == :delete
        # Recursively call 'deletion_query_parser' on association query, to delete any if the assoc's dependencies
        foreign_ids_by_type.each do |type, ids|
          assoc_klass = type.constantize
          deletion_query_parser(assoc_klass.where(id: ids), assoc_klass)
        end
      elsif type == :restricted
        if traverse_restricted_dependency_for_belongs_to_poly?(parent_class, reflection, foreign_ids_by_type)
          # Recursively call 'deletion_query_parser' on association query, to delete any if the assoc's dependencies
          foreign_ids_by_type.each do |type, ids|
            assoc_klass = type.constantize
            deletion_query_parser(assoc_klass.where(id: ids), assoc_klass)
          end
        end
      else
        raise "invalid parsing type: #{type}"
      end
    end

    # return [Boolean]
    # - true if valid
    # - false if not valid
    def traverse_restricted_dependency? parent_class, reflection, association_query
      # Return true if we're going to destroy all restricted
      return true if opts_c.force_destroy_restricted

      if association_query.any?
        report_error(
          "
            #{parent_class.name}'s assoc '#{reflection.name}' has a restricted dependency type.
            If you still wish to destroy, use the 'force_destroy_restricted: true' option
          "
        )
      end

      return false
    end

    # special use-case to detect restricted dependency for 'belongs_to polymorphic: true' use-case
    def traverse_restricted_dependency_for_belongs_to_poly? parent_class, reflection, ids_by_type
      # Return true if we're going to destroy all restricted
      return true if opts_c.force_destroy_restricted

      ids = ids_by_type.values.flatten
      if ids.any?
        report_error(
          "
            #{parent_class.name}'s assoc '#{reflection.name}' has a restricted dependency type.
            If you still wish to destroy, use the 'force_destroy_restricted: true' option
          "
        )
      end

      return false
    end

    def read_from_db(&block)
      puts "Reading from DB..." if opts_c.verbose
      opts_c.db_read_wrapper.call(block)
    end
  end
end
