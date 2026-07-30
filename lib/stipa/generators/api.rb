require_relative 'base'

module Stipa
  module Generators
    class Api < Base
      private

      def template_name = 'api'

      def dirs
        %w[config controllers models db/migrate]
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
          'Rakefile'                               => t_rakefile,
          'server.rb'                              => t_server,
          'config/database.rb'                     => t_database_config,
          'config/routes.rb'                       => t_routes(
            extra_requires: ['../controllers/health_controller'],
            extra_routes:   ["get '/health', to: 'health#show'"],
          ),
          'controllers/application_controller.rb' => t_application_controller,
          'controllers/health_controller.rb'       => t_health_controller,
          'models/application_model.rb'            => t_application_model,
          'db/migrate/001_create_posts.rb'         => t_migration_create_posts,
        }
      end

      def t_gitignore
        t_gitignore_common
      end

      def t_server
        <<~RUBY
          require 'stipa'
          require 'stipa/database'

          require_relative 'config/database'
          require_relative 'config/routes'

          Stipa::Database.connect!

          # Models must be loaded after the database connection is established.
          require_relative 'models/application_model'

          app = Stipa::App.new

          app.use Stipa::Middleware::RequestId
          app.use Stipa::Middleware::Timing
          app.use Stipa::Middleware::Cors

          Routes.draw(app)

          app.get '/api/health' do |_req, res|
            res.json({ status: 'ok', framework: 'Stipa', version: Stipa::VERSION, ts: Time.now.utc.iso8601 })
          end

          at_exit do
            Stipa::Database.disconnect!
          end

          app.start(host: '127.0.0.1', port: 3710)
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

            # ── Success helpers ──────────────────────────────

            def json(data, status: 200)
              res.status = status
              res.json(data)
            end

            def created!(data = nil)
              res.status = 201
              data ? res.json(data) : res.tap { _1.body = '' }
            end

            def no_content!
              res.status = 204
              res.body = ''
            end

            # ── Redirection ──────────────────────────────────

            def redirect_to(path, status: 302)
              res.status      = status
              res['Location'] = path
              res.body        = ''
            end

            # ── Error helpers ────────────────────────────────

            def bad_request!(message = 'Bad Request')
              error(400, message)
            end

            def unauthorized!(message = 'Unauthorized')
              error(401, message)
            end

            def forbidden!(message = 'Forbidden')
              error(403, message)
            end

            def not_found!(message = 'Not Found')
              error(404, message)
            end

            def conflict!(message = 'Conflict')
              error(409, message)
            end

            def unprocessable_entity!(message = 'Unprocessable Entity')
              error(422, message)
            end

            def too_many_requests!(message = 'Too Many Requests')
              error(429, message)
            end

            def internal_server_error!(message = 'Internal Server Error')
              error(500, message)
            end

            def error(status, message)
              res.status = status
              res.json(error: { message: message })
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
