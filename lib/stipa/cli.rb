require 'fileutils'
require_relative 'version'
require_relative 'generator'

module Stipa
  module CLI
    USAGE = <<~TEXT
      Stipa #{Stipa::VERSION} — Minimal Ruby HTTP Framework

      Usage:
        stipa new <app_name> [--vue|--api]

      Templates:
        --vue   MVC app with ERB views and Vue 3 components (default)
        --api   API-only app with JSON controllers, no views

      Examples:
        stipa new my_project
        stipa new my_project --vue
        stipa new my_api  --api

    TEXT

    def self.run(argv)
      command = argv[0]
      case command
      when 'new'
        name     = argv.reject { |a| a.start_with?('--') }[1]
        template = argv.find { |a| a.start_with?('--') }&.delete_prefix('--') || Generator::DEFAULT

        abort "Usage: stipa new <app_name> [--vue|--api]" if name.nil? || name.empty?

        Generator.new(name, template: template).generate
      else
        print USAGE
      end
    end
  end
end
