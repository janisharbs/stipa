require_relative 'model/uuid'
require_relative 'model/soft_delete'
require_relative 'model/serialization'
require_relative 'model/timestamps'
require_relative 'model/pagination'

module Stipa
  module Model
    def self.included(base)
      base.plugin :validation_helpers
      base.plugin :dirty

      base.include Timestamps
      base.include UUID
      base.include SoftDelete
      base.include Serialization
    end
  end
end
