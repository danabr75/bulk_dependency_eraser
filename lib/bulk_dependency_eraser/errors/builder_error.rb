module BulkDependencyEraser
  module Errors
    class BuilderError < BaseError
      attr_reader :original_error_klass, :building_klass_name

      def initialize(original_error_klass, message, building_klass_name:)
        @original_error_klass = original_error_klass
        @building_klass_name = building_klass_name
        super(message)
      end
    end
  end
end
