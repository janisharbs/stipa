require 'securerandom'

module Stipa
  # A minimal middleware stack inspired by Rack.
  #
  # Middleware signature:  call(req, res) -> res
  #
  # The stack is compiled ONCE at server start into a chain of nested
  # closures. Per-request cost is zero stack traversal — it's just
  # nested method calls. The first `use`-d middleware is outermost
  # (runs first on the way in, last on the way out).
  #
  # Example:
  #   app.use Stipa::Middleware::RequestId
  #   app.use Stipa::Middleware::Timing
  #   app.use Stipa::Middleware::Cors, origins: ['https://example.com']
  class MiddlewareStack
    def initialize
      @layers = []
    end

    def use(middleware, **options)
      @layers << [middleware, options]
      self
    end

    # Insert a middleware at the front of the stack (runs before all others).
    # Used internally by App to prepend Static before user middleware.
    def prepend(middleware, **options)
      @layers.unshift([middleware, options])
      self
    end

    # Compile the stack around `app` (the router callable).
    # Returns a single callable: call(req, res) -> res
    def build(app)
      # Reverse so first-added middleware ends up outermost
      @layers.reverse_each do |klass_or_proc, opts|
        inner = app
        app = if klass_or_proc.respond_to?(:new)
                klass_or_proc.new(inner, **opts)
              else
                # Plain lambda/proc: wrap so it receives next_app context
                ->(req, res) { klass_or_proc.call(req, res, inner) }
              end
      end
      app
    end

    def empty?; @layers.empty?; end
  end

  # ---------------------------------------------------------------------------
  # Built-in middleware
  # ---------------------------------------------------------------------------

  module Middleware
    # Propagates an upstream X-Request-Id header or mints a new one.
    # Runs before the router so req.id is always set when handlers execute.
    #
    # With a load balancer / API gateway that injects X-Request-Id, distributed
    # traces stay correlated across services automatically.
    class RequestId
      def initialize(next_app, header: 'X-Request-Id')
        @next_app = next_app
        @header   = header
      end

      def call(req, res)
        # Header lookup is lowercase in Request; header name for response is as-is
        req.id = req[@header.downcase] || SecureRandom.hex(8)
        res.set_header(@header, req.id)
        @next_app.call(req, res)
      end
    end

    # Records wall-clock time and appends X-Response-Time to the response.
    # Uses CLOCK_MONOTONIC (not Time.now) so system clock adjustments don't
    # produce negative or inflated durations.
    class Timing
      def initialize(next_app)
        @next_app = next_app
      end

      def call(req, res)
        t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = @next_app.call(req, res)
        ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(2)
        result.set_header('X-Response-Time', "#{ms}ms")
        result
      end
    end

    # Simple CORS headers. Handles OPTIONS preflight automatically.
    # Pass origins: ['*'] to allow all, or a specific list for allowlisting.
    class Cors
      def initialize(next_app, origins: ['*'],
                     methods: %w[GET POST PUT PATCH DELETE OPTIONS])
        @next_app = next_app
        @origins  = Array(origins)
        @methods  = methods.join(', ')
      end

      def call(req, res)
        origin  = req['origin']
        wildcard = @origins.include?('*')
        allowed  = wildcard || (origin && @origins.include?(origin))

        if allowed
          # Never reflect an arbitrary Origin back. When the allowlist is '*',
          # set the header to the literal '*'. When using an explicit list, only
          # echo origins that are actually in the list (already guaranteed by
          # the `allowed` check above).
          res.set_header('Access-Control-Allow-Origin',
                         wildcard ? '*' : origin)
          res.set_header('Access-Control-Allow-Methods', @methods)
          res.set_header('Access-Control-Allow-Headers',
                         'Content-Type, Authorization, X-Request-Id')
          # Vary tells caches that the response differs by Origin
          res.set_header('Vary', 'Origin') unless wildcard
        end

        # OPTIONS preflight: respond immediately without hitting the router
        if req.method == 'OPTIONS'
          res.status = 204
          return res
        end

        @next_app.call(req, res)
      end
    end
  end
end
