module Stipa
  module Model
    module SoftDelete
      def self.included(base)
        base.instance_eval do
          dataset_module do
            def deleted
              where(deleted_at: !nil)
            end

            def not_deleted
              where(deleted_at: nil)
            end
          end

          def self.dataset
            super.not_deleted
          end
        end
      end

      def soft_delete
        update(deleted_at: Time.now.utc)
      end

      def restore
        update(deleted_at: nil)
      end

      def deleted?
        !deleted_at.nil?
      end
    end
  end
end
