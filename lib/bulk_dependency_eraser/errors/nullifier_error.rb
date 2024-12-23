module BulkDependencyEraser
  module Errors
    class NullifierError < BaseError
      attr_reader :original_error_klass, :nullifying_klass_name, :nullifying_columns

      def initialize(original_error_klass, message, nullifying_klass_name:, nullifying_columns:)
        @original_error_klass = original_error_klass
        @nullifying_klass_name = nullifying_klass_name
        @nullifying_columns = nullifying_columns
        super(message)
      end
    end
  end
end
