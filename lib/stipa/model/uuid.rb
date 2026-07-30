require 'securerandom'

module Stipa
  module Model
    module UUID
      def self.included(base)
        base.class_eval do
          def before_create
            self.id ||= SecureRandom.uuid
            super
          end
        end
      end

      def to_param
        id
      end
    end
  end
end
