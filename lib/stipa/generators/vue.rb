require_relative 'base'

module Stipa
  module Generators
    class Vue < Base
      private

      def template_name = 'vue'

      def dirs
        %w[
          app/config
          app/controllers
          app/models
          app/views/layouts
          app/views/home
          app/components
          public/vendor
        ]
      end

      def post_generate
        copy_asset 'stipa-vue.js',   from: GEM_JS
        copy_asset 'logo.png',     from: GEM_MEDIA
        copy_asset 'favicon.ico',  from: GEM_MEDIA
      end

      def copy_asset(file, from:)
        src = File.join(from, file)
        if File.exist?(src)
          FileUtils.cp(src, File.join(target, "public/#{file}"))
          say "  create  public/#{file}"
        else
          say "  warn    #{file} not found — copy it manually to public/"
        end
      end

      def done_message
        <<~DONE

          Done! Next steps:
            cd #{name}
            bundle install
            npm install
            npm run build       # copies Vue from node_modules + compiles app bundle
            bundle exec ruby server.rb

          To upgrade Vue:
            npm install vue@3.x.x
            npm run build
        DONE
      end

      def files
        {
          '.gitignore'                             => t_gitignore,
          'Gemfile'                                => t_gemfile,
          'package.json'                           => t_package_json,
          'rollup.config.js'                       => t_rollup_config,
          'tsconfig.json'                          => t_tsconfig,
          'server.rb'                                      => t_server,
          'app/config/routes.rb'                         => t_routes(
            extra_requires: ['../controllers/home_controller', '../controllers/health_controller'],
            extra_routes:   ["get '/', to: 'home#index'", "get '/api/health', to: 'health#show'"],
            method_override: true,
          ),
          'app/controllers/application_controller.rb'   => t_application_controller,
          'app/controllers/home_controller.rb'           => t_home_controller,
          'app/controllers/health_controller.rb'         => t_health_controller,
          'app/views/layouts/application.html.erb'      => t_layout,
          'app/views/home/index.html.erb'                => t_home_index,
          'public/app.css'                               => t_app_css,
          'app/components/RequestCard.vue'               => t_request_card_vue,
          'app/main.ts'                                  => t_main_ts,
          'app/shims-vue.d.ts'                           => t_shims_vue,
        }
      end

      def t_gitignore
        t_gitignore_common + <<~GITIGNORE

          # Node
          node_modules/
          package-lock.json

          # Build output
          public/app.js
          public/app.js.map
          public/vendor/
        GITIGNORE
      end

      def t_package_json
        JSON.pretty_generate(
          name: name,
          private: true,
          type: 'module',
          scripts: {
            'copy:vue'  => 'cp node_modules/vue/dist/vue.esm-browser.prod.js public/vendor/vue.esm-browser.prod.js',
            build:       'npm run copy:vue && rollup -c',
            watch:       'rollup -c --watch',
            dev:         'npm run copy:vue && concurrently "STIPA_RELOAD=1 bundle exec ruby server.rb" "rollup -c --watch"',
            typecheck:   'vue-tsc --noEmit',
          },
          devDependencies: {
            'concurrently'              => '^8.0.0',
            'rollup'                    => '^4.0.0',
            'rollup-plugin-vue'         => '^6.0.0',
            '@rollup/plugin-typescript' => '^11.0.0',
            '@vue/compiler-sfc'         => '^3.4.0',
            'typescript'                => '^5.0.0',
            'vue'                       => '^3.4.0',
            'vue-tsc'                   => '^2.0.0',
          },
        ) + "\n"
      end

      def t_rollup_config
        <<~JS
          import vue from 'rollup-plugin-vue'
          import typescript from '@rollup/plugin-typescript'

          export default {
            input: 'app/main.ts',
            output: {
              file: 'public/app.js',
              format: 'es',
            },
            external: ['vue'],
            // rollup-plugin-vue handles <script lang="ts"> in .vue SFCs;
            // @rollup/plugin-typescript compiles app/main.ts and other plain .ts files.
            plugins: [vue(), typescript({ tsconfig: './tsconfig.json' })],
          }
        JS
      end

      def t_tsconfig
        JSON.pretty_generate(
          compilerOptions: {
            target:           'ESNext',
            module:           'ESNext',
            moduleResolution: 'bundler',
            strict:           true,
            skipLibCheck:     true,
            allowJs:          true,
          },
          include: ['app/**/*'],
        ) + "\n"
      end

      def t_server
        <<~RUBY
          require 'stipa'
          require_relative 'app/config/routes'

          APP_DIR = __dir__

          app = Stipa::App.new(
            views:  "\#{APP_DIR}/app/views",
            public: "\#{APP_DIR}/public",
          )

          app.use Stipa::Middleware::RequestId
          app.use Stipa::Middleware::Timing

          Routes.draw(app)

          app.get '/api/health' do |_req, res|
            res.json({ status: 'ok', framework: 'Stipa', version: Stipa::VERSION, ts: Time.now.utc.iso8601 })
          end

          app.start(host: '0.0.0.0', port: 3710)
        RUBY
      end

      def t_application_controller
        <<~RUBY
          require 'uri'

          class ApplicationController
            attr_reader :req, :res

            def initialize(req, res)
              @req    = req
              @res    = res
              @params = nil
            end

            private

            def render(template, locals: {}, layout: :default)
              res.render(template, locals: locals, layout: layout)
            end

            def redirect_to(path, status: 302)
              res.status      = status
              res['Location'] = path
              res.body        = ''
            end

            def not_found!(message = 'Not Found')
              res.status = 404
              res.body   = message
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

                if req['content-type']&.include?('application/x-www-form-urlencoded')
                  req.body.split('&').each do |pair|
                    next if pair.empty?
                    k, v = pair.split('=', 2)
                    p[k.to_sym] = URI.decode_www_form_component(v.to_s)
                  end
                end

                p
              end
            end

            def flash_notice = params[:flash]
          end
        RUBY
      end

      def t_home_controller
        <<~RUBY
          require_relative 'application_controller'

          class HomeController < ApplicationController
            def index
              render('home/index')
            end
          end
        RUBY
      end

      def t_health_controller
        <<~RUBY
          require 'time'
          require_relative 'application_controller'

          class HealthController < ApplicationController
            def show
              res.json({
                status:  'ok',
                method:  req.method,
                path:    req.path,
                host:    req['host'] || 'localhost:3710',
                version: Stipa::VERSION,
                ts:      Time.now.utc.iso8601,
              })
            end
          end
        RUBY
      end

      def t_layout
        <<~ERB
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title><%= content_for(:title) || '#{app_title}' %></title>
            <link rel="icon" href="/favicon.ico">
            <%= stylesheet_tag '/app.css' %>

            <%# Pin Vue version via importmap — upgrade by changing vue in package.json and rebuilding %>
            <script type="importmap">
              { "imports": { "vue": "/vendor/vue.esm-browser.prod.js" } }
            </script>

            <%# Stipa Vue bootstrapper — exposes window.StipaVue %>
            <%= stipa_vue_bootstrap %>

            <%# App bundle — registers components and mounts them %>
            <script type="module" src="/app.js"></script>

            <%# Measure time from first byte to DOMContentLoaded %>
            <script>const _t0 = performance.now()</script>
          </head>
          <body>
            <%= content %>
          </body>
          </html>
        ERB
      end

      def t_home_index
        <<~ERB
          <div class="circle-wrap">
            <div class="hoop"></div>
            <img src="/logo.png" alt="Stipa" class="logo">
            <div class="circle-text">
              <h1>STĪPA</h1>
              <div class="tagline">Lightweight. Ruby. Bare HTTP.</div>
            </div>
          </div>
          <div class="container">
            <div data-vue-component="RequestCard"></div>

            <div class="stats">
              <p>Stipa <%= h Stipa::VERSION %> | stdlib only | no gems</p>
            </div>
          </div>
        ERB
      end

      def t_app_css
        <<~CSS
          :root { --red: #cc0000; --black: #1a1a1a; --white: #f4f4f4; }

          body {
            background: var(--white);
            color: var(--black);
            font-family: 'Input Mono', 'Menlo', monospace;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            gap: 1.5rem;
            padding: 2rem 1rem;
            box-sizing: border-box;
          }

          .circle-wrap {
            position: relative;
            width: 300px;
            height: 300px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }

          .container { text-align: center; }

          .circle-text {
            position: relative;
            z-index: 2;
            text-align: center;
          }

          .logo {
            position: absolute;
            width: 220px;
            height: 220px;
            object-fit: contain;
            opacity: 0.1;
            z-index: 1;
          }

          .hoop {
            position: absolute;
            inset: 0;
            border: 2px solid var(--red);
            border-radius: 50%;
            animation: rotate 10s linear infinite;
            opacity: 0.1;
          }

          @keyframes rotate {
            from { transform: rotate(0deg) scale(1); }
            to   { transform: rotate(360deg) scale(1.1); }
          }

          h1 { font-size: 3rem; letter-spacing: -2px; margin: 0; }

          .tagline { color: var(--red); font-weight: bold; }

          .code-box {
            background: #eee;
            padding: 20px;
            border-radius: 4px;
            text-align: left;
            display: inline-block;
          }

          .stats {
            font-size: 0.8rem;
            border-top: 1px solid #ddd;
            padding-top: 1rem;
            color: #666;
          }

          code { font-family: 'Input Mono', 'Menlo', monospace; }
          .red  { color: #d33; }

          /* ── General pages (non-splash) ── */
          .page {
            max-width: 860px;
            margin: 0 auto;
            padding: 3rem 1.5rem 6rem;
          }
        CSS
      end



      def t_shims_vue
        <<~TS
          declare module '*.vue' {
            import type { DefineComponent } from 'vue'
            const component: DefineComponent
            export default component
          }
        TS
      end

      def t_main_ts
        <<~TS
          import RequestCard from './components/RequestCard.vue'

          // window.StipaVue is set by /stipa-vue.js, loaded as a module before this script.
          const { StipaVue } = window as any

          StipaVue.register('RequestCard', RequestCard)
          StipaVue.mount()
        TS
      end

      def t_request_card_vue
        <<~VUE
          <template>
            <div class="code-box">
              <code class="red"># Request Processed in {{ renderTime }}ms</code><br>
              <code>{{ line1 }}</code><br>
              <code>{{ line2 }}</code><br>
              <code>{{ line3 }}</code>
            </div>
          </template>

          <script lang="ts">
          import { defineComponent, ref, onMounted } from 'vue'

          export default defineComponent({
            name: 'RequestCard',
            setup() {
              const renderTime = ref('…')
              const line1 = ref('…')
              const line2 = ref('…')
              const line3 = ref('…')

              onMounted(async () => {
                renderTime.value = (performance.now() - (window._t0 || 0)).toFixed(1)

                try {
                  const d = await fetch('/api/health').then(r => r.json())
                  line1.value = d.method + ' ' + d.path + ' HTTP/1.1'
                  line2.value = 'Host: ' + d.host
                  line3.value = 'Status: 200 OK'
                } catch {
                  line1.value = 'Failed to load health data'
                }
              })

              return { renderTime, line1, line2, line3 }
            },
          })
          </script>
        VUE
      end
    end
  end
end
