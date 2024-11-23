module BulkDependencyEraser
  module Utils
    module Methods
      # To freeze all nested structures including hashes, arrays, and strings
      # Deep Freezing All Structures
      def deep_freeze(obj)
        case obj
        when Hash
          obj.each { |key, value| deep_freeze(key); deep_freeze(value) }
          obj.freeze
        when Array
          obj.each { |value| deep_freeze(value) }
          obj.freeze
        when String
          obj.freeze
        else
          obj.freeze if obj.respond_to?(:freeze)
        end
      end
    end

    include Methods
    extend Methods
  end
end
