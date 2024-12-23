module BulkDependencyEraser
  module Errors
    class DeleterError < BaseError
      attr_reader :original_error_klass, :deleting_klass_name

      def initialize(original_error_klass, message, deleting_klass_name:)
        @original_error_klass = original_error_klass
        @deleting_klass_name = deleting_klass_name
        super(message)
      end
    end
  end
end
