module BulkDependencyEraser
  # Create a flat map hash for each class that lists every dependency.
  class FullSchemaParser < Base
    DEFAULT_OPTS = {
      verbose: false,
    }

    attr_reader :flat_dependencies_per_klass

    @cached_flat_dependencies_per_klass = nil
    def self.reset_cache
      @cached_flat_dependencies_per_klass = nil
    end
    def self.set_cache(value)
      @cached_flat_dependencies_per_klass = value.freeze
    end
    def self.get_cache
      @cached_flat_dependencies_per_klass
    end

    def initialize(opts: {})
      # @flat_dependencies_per_klass Structure
      # {
      #   <class_name> => {
      #     has_dependencies: <Boolean>,
      #     foreign_keys: {
      #       <column_name>: <association_class_name>,
      #       ...
      #     },
      #     nullify_dependencies: {
      #       <association_name>: <association_class_name>,
      #       ...
      #     },
      #     destroy_dependencies: {
      #       <association_name>: <association_class_name>,
      #       ...
      #     }
      #   }
      # }
      @flat_dependencies_per_klass = {}
      super(opts:)
    end

    def execute
      unless self.class.get_cache.nil?
        @flat_dependencies_per_klass = self.class.get_cache
        return true
      end

      Rails.application.eager_load!

      ActiveRecord::Base.descendants.each do |model|
        begin
          next if model.abstract_class? # Skip abstract classes like ApplicationRecord
          next unless model.connection.table_exists?(model.table_name)
        rescue Exception => e
          report_error("EXECPTION ON #{model.name}; #{e.class}: #{e.message}")
          next
        end

        flat_dependencies_parser(model)
      end

      deep_freeze(@flat_dependencies_per_klass)
      self.class.set_cache(@flat_dependencies_per_klass)

      return true
    end

    def reset
      @flat_dependencies_per_klass = {}
      self.class.reset_cache
    end

    protected

    # @param klass [ActiveRecord::Base]
    # @param dependency_path [Array<ActiveRecord::Base>] - previously parsed klasses
    def flat_dependencies_parser klass
      raise "invalid klass: #{klass}" unless klass < ActiveRecord::Base

      if flat_dependencies_per_klass.include?(klass.name)
        raise "@dependencies_per_klass already contains #{klass.name}"
      end

      @flat_dependencies_per_klass[klass.name] ||= {
        nullify_dependencies: {},
        destroy_dependencies: {},
        has_many: {},
        belongs_to: {},
      }

      # We're including :restricted dependencies
      destroy_associations = klass.reflect_on_all_associations.select do |reflection|
        dependency_type = reflection.options&.dig(:dependent)
        dependency_type.to_sym if dependency_type.is_a?(String)
        DEPENDENCY_DESTROY.include?(dependency_type)
      end

      nullify_associations = klass.reflect_on_all_associations.select do |reflection|
        dependency_type = reflection.options&.dig(:dependent)
        dependency_type.to_sym if dependency_type.is_a?(String)
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

      destroy_association_names.uniq.each do |association_name|
        add_deletion_dependency_to_flat_map(klass, association_name)
      end

      nullify_association_names.uniq.each do |association_name|
        add_nullification_dependency_to_flat_map(klass, association_name)
      end

      # add has_many relationships
      (
        klass.reflect_on_all_associations(:has_many) + 
        klass.reflect_on_all_associations(:has_one) + 
        klass.reflect_on_all_associations(:has_and_belongs_to_many)
      ).each do |reflection|
        next if reflection.options[:through].present?

        add_has_many_to_flat_map(klass, reflection)
      end

      # add belongs_to relationships
      klass.reflect_on_all_associations(:belongs_to).each do |reflection|
        next if reflection.options[:through].present?

        add_belongs_to_to_flat_map(klass, reflection)
      end
    end

    # @param klass [ActiveRecord::Base]
    # @param association_name [Symbol] - name of the association
    def add_has_many_to_flat_map(klass, reflection)
      association_name = reflection.name
      @flat_dependencies_per_klass[klass.name][:has_many][association_name] = reflection.klass.name
    end

    # @param klass [ActiveRecord::Base]
    # @param association_name [Symbol] - name of the association
    def add_belongs_to_to_flat_map(klass, reflection)
      association_name = reflection.name
      reflection_klass_name = is_reflection_polymorphic?(reflection) ? POLY_KLASS_NAME : reflection.klass.name
      @flat_dependencies_per_klass[klass.name][:belongs_to][association_name] = reflection_klass_name
    end

    # @param klass [ActiveRecord::Base]
    # @param association_name [Symbol] - name of the association
    def add_deletion_dependency_to_flat_map(klass, association_name)
      reflection = klass.reflect_on_association(association_name)
      reflection_klass_name = is_reflection_polymorphic?(reflection) ? POLY_KLASS_NAME : reflection.klass.name
      @flat_dependencies_per_klass[klass.name][:destroy_dependencies][association_name] = reflection_klass_name
    end

    # @param klass [ActiveRecord::Base]
    # @param association_name [Symbol] - name of the association
    def add_nullification_dependency_to_flat_map(klass, association_name)
      reflection = klass.reflect_on_association(association_name)
      # nullifications can't be poly klass
      @flat_dependencies_per_klass[klass.name][:nullify_dependencies][association_name] = reflection.klass.name
    end

    # @param reflection [ActiveRecord::Reflection::AssociationReflection]
    def is_reflection_polymorphic?(reflection)
      reflection.options&.dig(:polymorphic) == true
    end
  end
end