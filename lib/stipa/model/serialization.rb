require 'json'

module Stipa
  module Model
    module Serialization
      def to_hash
        columns.each_with_object({}) do |col, h|
          h[col] = send(col)
        end
      end

      def to_json(*args)
        to_hash.to_json(*args)
      end

      def self.included(base)
        base.instance_eval do
          def from_json(json)
            new(JSON.parse(json))
          end
        end
      end
    end
  end
end
