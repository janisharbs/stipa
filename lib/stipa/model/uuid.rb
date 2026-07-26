require 'securerandom'

module Stipa
  module Model
    module UUID
      def self.included(base)
        base.instance_eval do
          before_create { self.id ||= SecureRandom.uuid }
        end
      end

      def to_param
        id
      end
    end
  end
end
