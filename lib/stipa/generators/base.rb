require 'fileutils'
require 'json'
require 'pathname'

module Stipa
  module Generators
    class Base
      GEM_JS   = File.expand_path('../../js', __dir__)
      GEM_MEDIA = File.expand_path('../../../media', __dir__)
      GEM_ROOT = File.expand_path('../..', GEM_JS)

      attr_reader :name, :target

      def initialize(name)
        @name   = name
        @target = File.expand_path(name, Dir.pwd)
      end

      def generate
        abort "Error: '#{name}' already exists." if Dir.exist?(target)

        say "Creating #{name} (#{template_name})..."
        make_dirs
        write_files
        post_generate
        init_git
        say done_message
      end

      private

      def make_dirs
        dirs.each { |d| FileUtils.mkdir_p(File.join(target, d)) }
      end

      def write_files
        files.each do |path, content|
          File.write(File.join(target, path), content)
          say "  create  #{path}"
        end
      end

      def post_generate = nil

      def init_git
        return unless git_available?

        Dir.chdir(target) do
          system('git init -q')
          system('git add .')
          system("git commit -q -m 'Initial commit'")
        end
        say '  git     initialized repository with initial commit'
      rescue => e
        say "  warn    git init failed: #{e.message}"
      end

      def say(msg) = puts(msg)

      def app_title
        name.split(/[-_]/).map(&:capitalize).join(' ')
      end

      def git_available?
        system('git --version > /dev/null 2>&1')
      end

      # ── Shared templates ───────────────────────────────────────────────────────

      def t_gitignore_common
        <<~GITIGNORE
          # Ruby
          .bundle/
          vendor/bundle/
          Gemfile.lock

          # OS
          .DS_Store
          Thumbs.db
          *.swp
          *.swo
        GITIGNORE
      end

      def t_gemfile
        <<~RUBY
          source 'https://rubygems.org'

          gem 'stipa'
        RUBY
      end

      def t_routes(extra_requires: [], extra_routes: [], method_override: false)
        requires = extra_requires.map { |r| "require_relative '#{r}'" }.join("\n")
        override = method_override ? <<~RUBY : ''
          # ── Method Override ────────────────────────────────────────────────────────
          # Allows HTML forms to tunnel PUT/DELETE via a hidden _method field.

          MethodOverride = lambda do |req, res, next_app|
            if req.method == 'POST' && req['content-type']&.include?('application/x-www-form-urlencoded')
              form = req.body.split('&').each_with_object({}) do |pair, h|
                k, v = pair.split('=', 2)
                h[k] = URI.decode_www_form_component(v.to_s) if k
              end
              override = form['_method']&.upcase
              req.instance_variable_set(:@method, override) if %w[PUT PATCH DELETE].include?(override)
            end
            next_app.call(req, res)
          end

        RUBY

        use_override = method_override ? "\n            @app.use MethodOverride\n" : ''
        routes_body  = extra_routes.map { |r| "            #{r}" }.join("\n")

        <<~RUBY
          require 'uri'
          #{requires}
          #{override}
          class Routes
            def self.draw(app) = new(app).draw

            def initialize(app)
              @app = app
            end

            def draw#{use_override}
          #{routes_body}
            end

            private

            def resolve(to)
              ctrl, action = to.split('#', 2)
              klass = Object.const_get(ctrl.split('_').map(&:capitalize).join + 'Controller')
              [klass, action.to_sym]
            end

            %w[get post put patch delete].each do |verb|
              define_method(verb) do |pattern, to:|
                klass, action = resolve(to)
                @app.public_send(verb, pattern) { |req, res| klass.new(req, res).public_send(action) }
              end
            end
          end
        RUBY
      end
    end
  end
end
