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
          system('git', 'init', '-q')
          system('git', 'add', '.')
          system('git', 'commit', '-q', '-m', 'Initial commit')
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
        system('git', '--version', out: File::NULL, err: File::NULL)
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
          gem 'sequel'
          gem 'dotenv'

          # Database adapter — uncomment the one you need:
          # gem 'pg'          # PostgreSQL
          # gem 'mysql2'      # MySQL / MariaDB
          # gem 'sqlite3'     # SQLite
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
              req.method = override if %w[PUT PATCH DELETE].include?(override)
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
              # 'admin/users' → 'Admin::UsersController'
              # 'users'       → 'UsersController'
              class_name = ctrl.split('/').map { |seg| seg.split('_').map(&:capitalize).join }.join('::') + 'Controller'
              klass = Object.const_get(class_name)
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

      def t_database_config
        <<~RUBY
          # frozen_string_literal: true

          environment = ENV.fetch('APP_ENV', 'development')

          case environment
          when 'development', 'test'
            require 'dotenv/load'
          end

          # Set DATABASE_URL in your .env file (development/test) or environment (production).
          #
          # PostgreSQL:
          #   DATABASE_URL=postgres://user:password@localhost:5432/myapp
          #
          # MySQL:
          #   DATABASE_URL=mysql2://user:password@localhost:3306/myapp
          #
          # SQLite:
          #   DATABASE_URL=sqlite://db/development.db

          Sequel.database_timezone = :utc
          Sequel.application_timezone = :local
        RUBY
      end

      def t_application_model
        <<~RUBY
          # frozen_string_literal: true

          require 'stipa/model'

          class ApplicationModel < Sequel::Model
            include Stipa::Model

            def self.dataset
              super
            rescue Sequel::Error => e
              raise "Database not ready: \#{e.message}"
            end
          end
        RUBY
      end

      def t_migration_create_posts
        <<~RUBY
          # frozen_string_literal: true

          Sequel.migration do
            change do
              create_table :posts do
                primary_key :id
                String  :title,       null: false
                String  :body,        text: true
                String  :slug,        null: false
                DateTime :created_at, null: false
                DateTime :updated_at, null: false

                index :slug, unique: true
              end
            end
          end
        RUBY
      end

      def t_rakefile
        <<~RUBY
          # frozen_string_literal: true

          require 'rake'
          require 'stipa/database'

          namespace :db do
            desc 'Run pending migrations'
            task :migrate do
              load_config
              Sequel::Migrator.run(Stipa::Database.connection, 'db/migrate')
              puts "Migrated to \#{Stipa::Database.connection[:schema_info].first[:version]}"
            end

            desc 'Rollback the last migration'
            task :rollback do
              load_config
              Sequel::Migrator.run(Stipa::Database.connection, 'db/migrate', target: current_version - 1)
              puts "Rolled back to \#{current_version}"
            end

            desc 'Show current migration version'
            task :version do
              load_config
              puts "Current version: \#{current_version}"
            end
          end

          task default: 'db:migrate'

          def load_config
            require_relative 'config/database'
            Stipa::Database.connect!
          end

          def current_version
            Stipa::Database.connection[:schema_info].first[:version]
          rescue
            0
          end
        RUBY
      end
    end
  end
end
