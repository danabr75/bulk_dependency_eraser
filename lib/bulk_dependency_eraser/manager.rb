module BulkDependencyEraser
  class Manager < Base
    DEFAULT_OPTS = {
      verbose: false,
    }.freeze

    delegate :nullification_list, :deletion_list, to: :dependency_builder
    delegate :ignore_table_deletion_list, :ignore_table_nullification_list, to: :dependency_builder

    # @param query [ActiveRecord::Base | ActiveRecord::Relation]
    def initialize query:, opts: {}
      @opts = opts
      @dependency_builder = BulkDependencyEraser::Builder.new(query:, opts:)
      @deleter   = nil
      @nullifier = nil

      @built = false
      super(opts:)
    end

    def execute
      unless built
        # return early if build fails
        return false unless build
      end

      nullify! && delete!

      return errors.none?
    end

    def build
      builder_execution = @dependency_builder.execute

      unless builder_execution
        puts "Builder execution FAILED" if opts_c.verbose
        merge_errors(dependency_builder.errors, 'Builder: ')
      else
        puts "Builder execution SUCCESSFUL" if opts_c.verbose
      end

      return builder_execution
    end

    def delete!
      @deleter  = BulkDependencyEraser::Deleter.new(class_names_and_ids: deletion_list, opts:)
      deleter_execution = deleter.execute
      unless deleter_execution
        puts "Deleter execution FAILED" if opts_c.verbose
        merge_errors(deleter.errors, 'Deleter: ')
      else
        puts "Deleter execution SUCCESSFUL" if opts_c.verbose
      end

      return deleter_execution
    end

    def nullify!
      @nullifier = BulkDependencyEraser::Nullifier.new(class_names_columns_and_ids: nullification_list, opts:)
      nullifier_execution = nullifier.execute

      unless nullifier_execution
        puts "Nullifier execution FAILED" if opts_c.verbose
        merge_errors(nullifier.errors, 'Nullifier: ')
      else
        puts "Nullifier execution SUCCESSFUL" if opts_c.verbose
      end

      return nullifier_execution
    end

    protected

    attr_reader :dependency_builder, :deleter, :nullifier, :opts, :built
  end
end
