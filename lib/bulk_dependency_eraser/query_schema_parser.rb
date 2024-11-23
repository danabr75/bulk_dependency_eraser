module BulkDependencyEraser
  class QuerySchemaParser < Base
    DEFAULT_OPTS = {
      verbose: false,
      # Some associations scopes take parameters.
      # - We would have to instantiate if we wanted to apply that scope filter.
      instantiate_if_assoc_scope_with_arity: false,
      force_destroy_restricted: false,
    }

    # attr_accessor :deletion_list, :nullification_list
    attr_reader :initial_class
    attr_reader :dependencies_per_klass
    attr_reader :circular_dependency_klasses
    attr_reader :full_schema_parser

    delegate :flat_dependencies_per_klass, to: :full_schema_parser

    def initialize query:, opts: {}
      if query.is_a?(ActiveRecord::Relation)
        @initial_class      = query.klass
      else
        # current_query is a normal rails class
        @initial_class      = query
      end
      # @dependencies_per_klass Structure
      # {
      #   <ActiveRecord::Base> => {
      #     <ActiveRecord::Reflection::AssociationReflection> => <ActiveRecord::Base> 
      #   }
      # }
      @dependencies_per_klass = {}
      # @circular_dependency_klasses Structure
      # {
      #   <ActiveRecord::Base> => [
      #     # Path of dependencies that start and end with the key class
      #     <ActiveRecord::Base>,
      #     <ActiveRecord::Base>,
      #     <ActiveRecord::Base>,
      #   ]
      # }
      @circular_dependency_klasses = {}
      @full_schema_parser = BulkDependencyEraser::FullSchemaParser.new(opts:)
      super(opts:)
    end

    def execute
      unless full_schema_parser.execute
        merge_errors(full_schema_parser.errors, 'FullSchemaParser: ')
        return false
      end
      klass_dependencies_parser(initial_class, klass_action: :destroy)

      @dependencies_per_klass.each do |key, values|
        @dependencies_per_klass[key] = values.uniq
      end

      return true
    end

    # @param klass [ActiveRecord::Base, Array<ActiveRecord::Base>]
    # - if was a dependency from a polymophic class, then iterate through the klasses.
    # @param dependency_path [Array<ActiveRecord::Base>] - previously parsed klasses
    def klass_dependencies_parser klass, klass_action:, dependency_path: []
      puts "KLASS #{klass.name}"
      puts klass_action.inspect
      puts dependency_path.inspect
      puts ""
      if klass.is_a?(Array)
        klass.each do |klass_subset|
          klass_dependencies_parser(klass_subset, klass_action:, dependency_path:)
        end
        return
      end

      unless DEPENDENCY_DESTROY.include?(klass_action) || DEPENDENCY_NULLIFY.include?(klass_action)
        raise "invalid klass action: #{klass_action}"
      end
      raise "invalid klass: #{klass}" unless klass < ActiveRecord::Base

      # Not a circular dependency if the repetitious klass has a nullify action.
      if DEPENDENCY_DESTROY.include?(klass_action) && dependency_path.include?(klass.name)
        index = dependency_path.index(klass.name)
        circular_dependency = dependency_path[index..] + [klass.name]
        circular_dependency_klasses[klass.name] = circular_dependency
        return
      end

      # We don't need to consider dependencies for a klass that is being nullified.
      return if DEPENDENCY_NULLIFY.include?(klass_action)

      # already parsed, doesn't need to be parsed again.
      puts "RETURNING EARLY, arleady parsed" if dependencies_per_klass.include?(klass.name)
      return if dependencies_per_klass.include?(klass.name)

      @dependencies_per_klass[klass.name] = []

      # We're including :restricted dependencies
      destroy_associations = klass.reflect_on_all_associations.select do |reflection|
        dependency_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_DESTROY.include?(dependency_type)
      end

      nullify_associations = klass.reflect_on_all_associations.select do |reflection|
        dependency_type = reflection.options&.dig(:dependent)&.to_sym
        DEPENDENCY_NULLIFY.include?(dependency_type)
      end

      # Iterate through the assoc names, if there are any :through assocs, then rename the association
      # - Rails interpretation of any dependencies of a :through association is to apply it to
      #   the leaf association at the end of the :through chain(s)
      destroy_association_names = destroy_associations.map(&:name).collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end
      nullify_association_names = nullify_associations.map(&:name).collect do |assoc_name|
        find_root_association_from_through_assocs(klass, assoc_name)
      end

      puts "DESTROYABLES"
      puts destroy_association_names.uniq.inspect
      puts ""

      destroy_association_names.uniq.each do |association_name|
        association_parser(klass, association_name, dependency_path)
      end

      nullify_association_names.uniq.each do |association_name|
        association_parser(klass, association_name, dependency_path)
      end
    end

    # Used to iterate through each destroyable association, and recursively call 'deletion_query_parser'.
    # @param parent_class     [ApplicationRecord]
    # @param association_name [Symbol]                - The association name from the parent_class
    def association_parser(parent_class, association_name, dependency_path)
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name
      dependency_type = reflection.options.dig(:dependent)

      case reflection_type
      when 'ActiveRecord::Reflection::HasManyReflection'
        puts "HAS_MANY: #{association_name}"
        association_parser_has_many(parent_class, association_name, dependency_type, dependency_path)
      when 'ActiveRecord::Reflection::HasOneReflection'
        puts "HAS_ONE: #{association_name}"
        association_parser_has_many(parent_class, association_name, dependency_type, dependency_path)
      when 'ActiveRecord::Reflection::BelongsToReflection'
        puts "BELONGS_TO: #{association_name}"
        association_parser_belongs_to(parent_class, association_name, dependency_type, dependency_path)
      else
        report_message("Unsupported association type for #{parent_class.name}'s association '#{association_name}': #{reflection_type}")
      end
    end

    # Handles the :has_many association type
    # - handles it's polymorphic associations internally (easier on the has_many)
    def association_parser_has_many(parent_class, association_name, dependency_type, dependency_path)
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      assoc_klass = reflection.klass
      assoc_klass_name = assoc_klass.name
      @dependencies_per_klass[parent_class.name] << assoc_klass.name

      # If there is an association scope present, check to see how many parameters it's using
      # - if there's any parameter, we have to either skip it or instantiate it to find it's dependencies.
      if reflection.scope&.arity&.nonzero? && opts_c.instantiate_if_assoc_scope_with_arity == false
        report_error(
          "#{parent_class.name} and '#{association_name}' - scope has instance parameters. Use :instantiate_if_assoc_scope_with_arity option?"
        )
        return
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
        else
          specified_foreign_key = parent_class.table_name.singularize + "_id"
        end
      end

      # Check to see if foreign_key exists in association class's table
      unless assoc_klass.column_names.include?(specified_foreign_key)
        report_error(
          "
          For '#{assoc_klass.name}': Could not determine the assoc's foreign key.
          Foreign key should have been '#{specified_foreign_key}', but did not exist on the #{assoc_klass.table_name} table.
          "
        )
        return
      end

      unless specified_foreign_type.nil? || assoc_klass.column_names.include?(specified_foreign_type)
        report_error(
          "
          For '#{assoc_klass.name}': Could not determine the assoc's foreign key type.
          Foreign key type should have been '#{specified_foreign_type}', but did not exist on the #{assoc_klass.table_name} table.
          "
        )
      end

      if dependency_type == :restricted && traverse_restricted_dependency?(parent_class, reflection)
        klass_dependencies_parser(assoc_klass, klass_action: dependency_type, dependency_path: dependency_path.dup << parent_class.name)
      else
        klass_dependencies_parser(assoc_klass, klass_action: dependency_type, dependency_path: dependency_path.dup << parent_class.name)
      end
    end

    def association_parser_belongs_to(parent_class, association_name, dependency_type, dependency_path)
      puts "association_parser_belongs_to"
      reflection = parent_class.reflect_on_association(association_name)
      reflection_type = reflection.class.name

      is_polymorphic = reflection.options[:polymorphic]
      if is_polymorphic
        @dependencies_per_klass[parent_class.name] += find_klasses_from_polymorphic_dependency(parent_class)
      else
        assoc_klass = reflection.klass
        @dependencies_per_klass[parent_class.name] << assoc_klass.name
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
      puts "GOT HERE, AND MIGHT BE WRONG: #{dependency_type}"
      if (
        DEPENDENCY_DESTROY.include?(dependency_type) ||
        DEPENDENCY_NULLIFY.include?(dependency_type) && traverse_restricted_dependency?(parent_class, reflection)
      )
        puts "FOR #{parent_class.name}'s ASSOCIATION #{association_name}, calling"
        puts "klass_dependencies_parser(#{assoc_klass}, dependency_path: #{dependency_path.dup << parent_class.name})"
        klass_dependencies_parser(assoc_klass, klass_action: dependency_type, dependency_path: dependency_path.dup << parent_class.name)
      end
    end

    # In this example the klass would be the polymorphic klass
    # - i.e. Attachment belongs_to: :attachable, dependent: :destroy
    # We're looking for klasses in the flat map that have a has_many :attachments, as: :attachable
    def find_klasses_from_polymorphic_dependency(klass)
      found_klasses = []
      flat_dependencies_per_klass.each do |flat_klass_name, klass_dependencies|
        if klass_dependencies[:has_many].values.include?(klass.name)
          found_klasses << flat_klass_name
        end
      end
      found_klasses
    end

    # return [Boolean]
    # - true if valid
    # - false if not valid
    def traverse_restricted_dependency? parent_class, reflection
      # Return true if we're going to destroy all restricted
      return true if opts_c.force_destroy_restricted

      report_error(
        "
          #{parent_class.name}'s assoc '#{reflection.name}' has a restricted dependency type.
          If you still wish to destroy, use the 'force_destroy_restricted: true' option
        "
      )

      return false
    end

  end
end