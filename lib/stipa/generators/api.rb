require_relative 'base'

module Stipa
  module Generators
    class Api < Base
      private

      def template_name = 'api'

      def dirs
        %w[config controllers]
      end

      def done_message
        <<~DONE

          Done! Next steps:
            cd #{name}
            bundle install
            bundle exec ruby server.rb
        DONE
      end

      def files
        {
          '.gitignore'                             => t_gitignore,
          'Gemfile'                                => t_gemfile,
          'server.rb'                              => t_server,
          'config/routes.rb'                       => t_routes(
            extra_requires: ['../controllers/health_controller'],
            extra_routes:   ["get '/health', to: 'health#show'"],
          ),
          'controllers/application_controller.rb' => t_application_controller,
          'controllers/health_controller.rb'       => t_health_controller,
        }
      end

      def t_gitignore
        t_gitignore_common
      end

      def t_server
        <<~RUBY
          require 'stipa'
          require_relative 'config/routes'

          app = Stipa::App.new

          app.use Stipa::Middleware::RequestId
          app.use Stipa::Middleware::Timing
          app.use Stipa::Middleware::Cors

          Routes.draw(app)

          app.start(host: '0.0.0.0', port: 3710)
        RUBY
      end

      def t_application_controller
        <<~RUBY
          require 'uri'
          require 'json'

          class ApplicationController
            attr_reader :req, :res

            def initialize(req, res)
              @req    = req
              @res    = res
              @params = nil
            end

            private

            def json(data, status: 200)
              res.status = status
              res.json(data)
            end

            def not_found!(message = 'Not found')
              res.status = 404
              res.json(error: message)
              throw :halt
            end

            def unprocessable!(errors)
              res.status = 422
              res.json(errors: errors)
              throw :halt
            end

            def params
              @params ||= begin
                p = req.params.dup

                req.query_string.split('&').each do |pair|
                  next if pair.empty?
                  k, v = pair.split('=', 2)
                  p[k.to_sym] = URI.decode_www_form_component(v.to_s)
                end

                if req['content-type']&.include?('application/json')
                  begin
                    body = JSON.parse(req.body, symbolize_names: true)
                    p.merge!(body) if body.is_a?(Hash)
                  rescue JSON::ParserError
                    # ignore malformed JSON body
                  end
                end

                p
              end
            end
          end
        RUBY
      end

      def t_health_controller
        <<~RUBY
          require_relative 'application_controller'

          class HealthController < ApplicationController
            def show
              json(status: 'ok', framework: 'Stipa', version: Stipa::VERSION, ts: Time.now.utc.iso8601)
            end
          end
        RUBY
      end
    end
  end
end
