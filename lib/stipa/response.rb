require 'json'

module Stipa
  # Builds a valid HTTP/1.1 response and serializes it to wire bytes.
  #
  # Design notes:
  #   - Content-Length is ALWAYS computed from body.bytesize in to_http,
  #     never stored manually. This prevents handler authors from setting
  #     a wrong value and makes binary correctness automatic.
  #   - Header names are stored in Title-Case for wire compatibility but
  #     set_header accepts any casing for developer ergonomics.
  #   - Keep-alive vs Connection:close is decided in to_http based on the
  #     request's HTTP version, so handler code never needs to think about it.
  #   - The Date header is injected automatically — required by RFC 7231.
  class Response
    STATUS_MESSAGES = {
      200 => 'OK',
      201 => 'Created',
      204 => 'No Content',
      301 => 'Moved Permanently',
      302 => 'Found',
      304 => 'Not Modified',
      400 => 'Bad Request',
      401 => 'Unauthorized',
      403 => 'Forbidden',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      408 => 'Request Timeout',
      413 => 'Payload Too Large',
      422 => 'Unprocessable Entity',
      429 => 'Too Many Requests',
      500 => 'Internal Server Error',
      502 => 'Bad Gateway',
      503 => 'Service Unavailable',
      504 => 'Gateway Timeout',
    }.freeze

    attr_accessor :status, :body, :template_engine
    attr_reader   :headers

    def initialize
      @status          = 200
      @headers         = {}
      @body            = ''
      @template_engine = nil
    end

    # Set a response header. Name is normalized to Title-Case.
    # Accepts any casing: set_header('content-type', 'text/html') is fine.
    def set_header(name, value)
      @headers[titlecase(name)] = value.to_s
    end
    alias []= set_header

    def [](name)
      @headers[titlecase(name)]
    end

    # Render an ERB template and set the body + Content-Type to text/html.
    #
    # Requires a template engine to be configured on the app:
    #   app = Stipa::App.new(views: 'views')
    #
    # Examples:
    #   res.render('home')
    #   res.render('users/show', locals: { user: @user })
    #   res.render('welcome',    locals: { name: 'Alice' }, layout: false)
    #   res.render('dashboard',  layout: 'layouts/admin')
    #
    # Returns self for chaining.
    def render(template, locals: {}, layout: :default)
      raise 'No template engine configured. Pass views: "path" to Stipa::App.new.' \
        unless @template_engine

      set_header('Content-Type', 'text/html; charset=utf-8')
      @body = @template_engine.render(template, locals: locals, layout: layout)
      self
    end

    # Set body to a JSON representation of `data` and set Content-Type.
    # Returns self so it can be used as the last expression in a handler.
    def json(data)
      @body = JSON.generate(data)
      set_header('Content-Type', 'application/json; charset=utf-8')
      self
    end

    # Serialize to the exact HTTP/1.1 bytes to write to the socket.
    # `req` is used to decide the Connection header (keep-alive or close).
    def to_http(req = nil)
      # Force binary encoding so bytesize is always the byte count,
      # not the character count (matters for multi-byte UTF-8 bodies).
      body_bytes = @body.to_s.b

      finalize_headers(body_bytes, req)

      status_text  = STATUS_MESSAGES.fetch(@status, 'Unknown')
      status_line  = "HTTP/1.1 #{@status} #{status_text}"
      header_block = @headers.map { |k, v| "#{k}: #{v}" }.join("\r\n")

      # RFC 7230: blank line (CRLF CRLF) separates header block from body
      "#{status_line}\r\n#{header_block}\r\n\r\n#{body_bytes}"
    end

    private

    # Inject protocol-level headers last so handlers cannot accidentally
    # set a wrong Content-Length or omit a required header.
    def finalize_headers(body_bytes, req)
      # Content-Length: always recomputed from actual bytes
      set_header('Content-Length', body_bytes.bytesize)

      # Default Content-Type if handler didn't set one
      set_header('Content-Type', 'text/plain; charset=utf-8') \
        unless @headers.key?('Content-Type')

      # Date: required by RFC 7231 §7.1.1.2
      set_header('Date', Time.now.utc.strftime('%a, %d %b %Y %H:%M:%S GMT'))

      # Server: identifies the framework
      set_header('Server', "Stipa/#{Stipa::VERSION}")

      inject_connection_header(req) if req
    end

    # Set Connection header based on HTTP version and client's preference.
    # HTTP/1.1 defaults to keep-alive; HTTP/1.0 defaults to close.
    def inject_connection_header(req)
      if keep_alive?(req)
        set_header('Connection', 'keep-alive')
        set_header('Keep-Alive', 'timeout=5, max=100')
      else
        set_header('Connection', 'close')
      end
    end

    def keep_alive?(req)
      return false if @status >= 500   # always close after server errors
      conn = req['connection']&.downcase
      req.http_version == 'HTTP/1.1' ? conn != 'close' : conn == 'keep-alive'
    end

    # Convert any casing to HTTP Title-Case: "content-type" → "Content-Type"
    def titlecase(name)
      name.to_s.split('-').map(&:capitalize).join('-')
    end
  end
end
