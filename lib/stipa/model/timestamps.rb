module Stipa
  module Model
    module Timestamps
      def self.included(base)
        base.instance_eval do
          plugin :timestamps,
                 create: :created_at,
                 update: :updated_at,
                 update_on_create: true
        end
      end
    end
  end
end
