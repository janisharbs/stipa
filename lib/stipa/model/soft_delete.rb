module Stipa
  module Model
    # Soft delete support for Sequel models.
    #
    # Provides `soft_delete`, `restore`, and `deleted?` instance methods,
    # plus `deleted` and `not_deleted` dataset scopes.
    #
    # Your table must have a nullable `deleted_at` timestamp column.
    #
    #   # db/migrate/001_create_posts.rb
    #   create_table :posts do
    #     primary_key :id
    #     DateTime :deleted_at
    #     # ...
    #   end
    #
    # ==== Opt into the default scope
    #
    # By default, soft-deleted rows are NOT filtered from queries.
    # To exclude them automatically, override `dataset` in your model:
    #
    #   class Post < ApplicationModel
    #     def self.dataset
    #       super.not_deleted
    #     end
    #   end
    #
    #   Post.where(title: "foo")  # => WHERE (deleted_at IS NULL) AND (title = 'foo')
    #
    # Without the override, include records as usual:
    #
    #   Post.where(title: "foo")  # => WHERE (title = 'foo')
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
        end
      end

      # Mark the record as soft-deleted.
      #
      #   post.soft_delete        # sets deleted_at = now
      #   post.soft_delete        # no-op (already deleted)
      def soft_delete
        update(deleted_at: Time.now.utc)
      end

      # Restore a soft-deleted record.
      #
      #   post.restore            # sets deleted_at = nil
      def restore
        update(deleted_at: nil)
      end

      # Returns +true+ if the record has been soft-deleted.
      def deleted?
        !deleted_at.nil?
      end
    end
  end
end
