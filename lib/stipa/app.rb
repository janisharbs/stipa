require_relative 'version'
require_relative 'logger'
require_relative 'server/server'
require_relative 'middleware/stack'
require_relative 'http/request'
require_relative 'http/response'

module Stipa
  # User-facing DSL for defining routes and middleware.
  #
  # Usage:
  #
  #   app = Stipa::App.new
  #
  #   app.use Stipa::Middleware::RequestId
  #   app.use Stipa::Middleware::Timing
  #   app.use Stipa::Middleware::Cors, origins: ['https://example.com']
  #
  #   app.get '/'            { |_req, res| res.body = 'Hello' }
  #   app.get '/health'      { |_req, res| res.json(status: 'ok') }
  #   app.post '/echo'       { |req, res|  res.body = req.body }
  #   app.get %r{/users/(?<id>\d+)} { |req, res| res.json(id: req.params[:id].to_i) }
  #
  #   app.start(port: 3710)
  #
  # Handler signature:
  #   Handlers always receive (req, res) — both the Request and the Response.
  #   Mutate `res` directly: res.body = ..., res.status = ..., res.json(...).
  #   Return value of the block is ignored; mutating `res` is the contract.
  #
  # Route matching:
  #   - String patterns: exact path match only.
  #   - Regexp patterns: full match via Regexp#match. Named capture groups
  #     (e.g., (?<id>\d+)) are placed into req.params as symbol keys.
  #   - Routes are checked in insertion order; first match wins.
  #
  # Middleware:
  #   - call `use` before `start`. Order matters: first `use`-d runs first.
  #   - The chain is compiled once at start time; calling `use` afterwards
  #     has no effect (a warning is logged).
  class App
    HTTP_VERBS = %w[get post put patch delete head options].freeze

    # views:  path to the views directory (enables ERB rendering via res.render)
    # public: path to the public directory (enables static file serving)
    #         When provided, Static middleware is automatically prepended.
    def initialize(views: nil, public: nil)
      @routes          = []
      @stack           = MiddlewareStack.new
      @started         = false
      @logger          = Logger.new
      @template_engine = views  ? Template.new(views_dir: views)  : nil
      @public_dir      = public ? File.expand_path(public)        : nil
    end

    # DSL: register a route for the given HTTP verb.
    # Pattern can be a String (exact match) or Regexp (with named captures).
    HTTP_VERBS.each do |verb|
      define_method(verb) do |pattern, &handler|
        @routes << [verb.upcase, pattern, handler]
      end
    end

    # Add a middleware to the stack. Must be called before start.
    def use(middleware, **opts)
      if @started
        @logger.warn("use() called after start — #{middleware} will be ignored")
        return self
      end
      @stack.use(middleware, **opts)
      self
    end

    # Build the middleware chain and start the TCP server. Blocks until shutdown.
    def start(**opts)
      @started = true
      # Prepend Static middleware automatically when a public dir is configured.
      # It runs before all user-registered middleware so static assets are served
      # without going through the full middleware stack.
      if @public_dir
        @stack.prepend(Middleware::Static, root: @public_dir)
      end
      chain = @stack.build(method(:dispatch))
      Server.new(app: chain, **opts).start
    end

    private

    # Core router — the innermost callable in the middleware chain.
    # Matches req.method + req.path against registered routes.
    # Sets req.params from Regexp named captures and calls the handler.
    def dispatch(req, res)
      @routes.each do |method, pattern, handler|
        next unless method == req.method

        match = case pattern
                when String
                  if pattern.include?(':')
                    # Colon-segment pattern: /users/:id → named-capture Regexp
                    re = pattern.gsub(%r{:([a-zA-Z_][a-zA-Z0-9_]*)}) { "(?<#{Regexp.last_match(1)}>[^/]+)" }
                    Regexp.new("\\A#{re}\\z").match(req.path)
                  else
                    # Exact string match
                    req.path == pattern ? true : nil
                  end
                when Regexp
                  # Full Regexp match — named captures become req.params
                  pattern.match(req.path)
                end

        next unless match

        # Populate req.params from named captures (for Regexp routes)
        if match.respond_to?(:named_captures)
          req.params = match.named_captures.transform_keys(&:to_sym)
        end

        res.template_engine = @template_engine if @template_engine
        handler.call(req, res)
        return res
      end

      # No route matched
      res.status = 404
      res.body   = "Not Found: #{req.method} #{req.path}"
      res
    end
  end
end
