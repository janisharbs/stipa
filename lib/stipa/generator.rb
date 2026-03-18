require_relative 'generators/base'
require_relative 'generators/vue'
require_relative 'generators/api'

module Stipa
  module Generator
    TEMPLATES = {
      'vue' => Generators::Vue,
      'api' => Generators::Api,
    }.freeze

    DEFAULT = 'vue'

    def self.new(name, template: DEFAULT)
      klass = TEMPLATES.fetch(template) { abort "Unknown template '#{template}'. Available: #{TEMPLATES.keys.join(', ')}" }
      klass.new(name)
    end
  end
end
