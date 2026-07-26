module Stipa
  module Model
    module Pagination
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def paginate(page: 1, per_page: 20)
          page  = [page.to_i, 1].max
          per_page = [per_page.to_i, 1].max

          total   = count
          records = limit(per_page).offset((page - 1) * per_page).all
          total_pages = (total.to_f / per_page).ceil

          {
            records:      records,
            page:         page,
            per_page:     per_page,
            total:        total,
            total_pages:  total_pages,
          }
        end
      end
    end
  end
end
