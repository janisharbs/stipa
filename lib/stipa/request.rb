module Stipa
  # Raised for any HTTP/1.1 protocol violation.
  # Caught by Connection#dispatch and turned into a 400 response.
  # Not a subclass of StandardError to avoid accidental rescue-all clauses
  # catching it — but we keep it as StandardError for practical simplicity.
  class BadRequest < StandardError; end

  # Parses a raw HTTP/1.1 header block (already read by Connection) and
  # reads the body from the socket using Content-Length.
  #
  # Design notes:
  #   - Headers are stored with lower-cased keys for O(1) case-insensitive
  #     lookup (RFC 7230 §3.2: header names are case-insensitive).
  #   - Body is read with IO.select + read_nonblock rather than SO_RCVTIMEO
  #     because SO_RCVTIMEO behaves inconsistently across Ruby versions and
  #     platforms. IO.select releases the GVL while waiting.
  #   - `id` and `params` are writable: RequestId middleware sets `id`,
  #     the router sets `params` after matching.
  #   - We reject header folding (obsolete since RFC 7230) with a 400.
  #   - Chunked Transfer-Encoding is not supported in this version.
  class Request
    MAX_HEADER_SIZE = 8 * 1024          #  8 KB — slow-loris defence
    MAX_BODY_SIZE   = 1 * 1024 * 1024   #  1 MB default; configurable per-server
    VALID_METHODS   = %w[GET POST PUT PATCH DELETE HEAD OPTIONS TRACE CONNECT].freeze

    attr_accessor :id, :params
    attr_reader   :method, :path, :query_string, :http_version,
                  :headers, :body, :bytes_in

    # Factory — called by Connection after reading the header block.
    #
    # @param raw_headers    [String]  everything up to (not including) \r\n\r\n
    # @param socket         [Socket]  live socket for reading remaining body bytes
    # @param peer           [String]  remote address string (for error messages)
    # @param body_timeout   [Numeric] seconds allowed for body read
    # @param socket_buffer  [String]  body bytes already read by Connection
    #                                 when it over-read past the header boundary
    # @param config         [Hash]    server-level config overrides
    def self.parse(raw_headers, socket:, peer:, body_timeout:,
                   socket_buffer: '', config: {})
      new(raw_headers, socket:, peer:, body_timeout:,
          socket_buffer:, config:)
    end

    def initialize(raw_headers, socket:, peer:, body_timeout:,
                   socket_buffer: '', config: {})
      @socket        = socket
      @peer          = peer
      @body_timeout  = body_timeout
      @socket_buffer = socket_buffer.b   # binary copy of pre-read body bytes
      @max_body      = config.fetch(:max_body_size, MAX_BODY_SIZE)
      @bytes_in      = raw_headers.bytesize
      @id            = nil   # set by RequestId middleware
      @params        = {}    # set by App#dispatch after route match
      parse_headers(raw_headers)
      read_body
    end

    # Case-insensitive header lookup: req['Content-Type'] or req['content-type']
    def [](name)
      @headers[name.to_s.downcase]
    end

    private

    def parse_headers(raw)
      lines = raw.split("\r\n", -1)
      raise BadRequest, 'empty request' if lines.empty? || lines[0].empty?

      parse_request_line(lines.shift)

      @headers = {}
      lines.each do |line|
        # RFC 7230 §3.2.4: header field folding is obsolete — reject with 400
        raise BadRequest, 'header folding not supported' if line.start_with?(' ', "\t")
        name, value = line.split(':', 2)
        raise BadRequest, "malformed header: #{line.inspect}" unless value
        # RFC 7230: no whitespace between field name and colon
        raise BadRequest, "whitespace before colon" if name != name.rstrip
        @headers[name.downcase.strip] = value.strip
      end
    end

    def parse_request_line(line)
      parts = line.split(' ', 3)
      raise BadRequest, "bad request line: #{line.inspect}" unless parts.length == 3

      @method, full_path, @http_version = parts

      raise BadRequest, "unknown method: #{@method}" unless VALID_METHODS.include?(@method)
      raise BadRequest, "unknown HTTP version: #{@http_version}" \
        unless @http_version.match?(/\AHTTP\/1\.[01]\z/)

      # Separate path from query string
      if (q = full_path.index('?'))
        @path         = full_path[0, q]
        @query_string = full_path[q + 1..]
      else
        @path         = full_path
        @query_string = ''
      end
    end

    def read_body
      cl = @headers['content-length']
      unless cl
        @body = ''
        return
      end

      # Integer() raises ArgumentError on non-numeric strings
      begin
        length = Integer(cl, 10)
      rescue ArgumentError
        raise BadRequest, "invalid Content-Length: #{cl.inspect}"
      end

      raise BadRequest, 'negative Content-Length' if length < 0
      raise BadRequest, "body exceeds #{@max_body} bytes limit" if length > @max_body

      @body      = read_exactly(length)
      @bytes_in += @body.bytesize
    end

    # Read exactly `n` bytes for the body.
    #
    # Drains @socket_buffer first (bytes already read by Connection when it
    # over-read past the header/body boundary), then reads remaining bytes
    # from the live socket using IO.select + read_nonblock.
    #
    # GVL note: IO.select releases the GVL while waiting, so other Ruby
    # threads continue running during I/O waits.
    def read_exactly(n)
      return '' if n == 0

      # Start with whatever Connection already buffered
      buf = @socket_buffer.byteslice(0, n) || ''
      buf = String.new(buf, encoding: 'BINARY')

      return buf if buf.bytesize >= n   # entire body was pre-buffered

      deadline = Time.now + @body_timeout

      while buf.bytesize < n
        remaining = deadline - Time.now
        raise BadRequest, 'body read timeout' if remaining <= 0

        readable = IO.select([@socket], nil, nil, remaining)
        raise BadRequest, 'body read timeout' if readable.nil?

        want  = [n - buf.bytesize, 65_536].min
        chunk = @socket.read_nonblock(want, exception: false)

        raise BadRequest, 'unexpected EOF during body read' if chunk.nil?
        next if chunk == :wait_readable   # spurious wakeup, retry

        buf << chunk
      end

      buf
    end
  end
end
