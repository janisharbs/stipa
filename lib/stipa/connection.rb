require 'socket'

module Stipa
  # Manages the HTTP/1.1 keep-alive request/response loop for a single socket.
  #
  # A Connection is created by the Server for every accepted TCP socket and
  # runs inside a worker thread from the ThreadPool. It owns the socket for
  # the lifetime of the keep-alive session and closes it on exit.
  #
  # Keep-alive protocol:
  #   HTTP/1.1: persistent by default. We close when:
  #     - client sends "Connection: close"
  #     - we've served max_requests on this connection
  #     - a read/write timeout fires (slow client or idle connection)
  #     - a parse error occurs (send 400, close — client is misbehaving)
  #     - an unhandled exception occurs (send 500, close)
  #   HTTP/1.0: close by default unless client sends "Connection: keep-alive"
  #
  # Timeout strategy (using IO.select, not SO_RCVTIMEO):
  #   - header_read_timeout (10s): time to receive the full header block.
  #     Applied to the FIRST request on a new connection. Defeats slow-loris.
  #   - keepalive_timeout (5s): idle time allowed BETWEEN requests on a
  #     persistent connection. Much shorter than header_read_timeout.
  #   - body_read_timeout (30s): time to read the request body after headers.
  #   - write_timeout (10s): time to flush the full response to the client.
  #
  # Why IO.select instead of SO_RCVTIMEO?
  #   SO_RCVTIMEO raises Errno::EAGAIN or EWOULDBLOCK inconsistently across
  #   Ruby versions, especially in combination with Ruby's IO buffering. IO.select
  #   is pure Ruby scheduler: it releases the GVL while waiting, allows other
  #   threads to run, and works identically on Linux, macOS, and JRuby.
  class Connection
    CRLF2 = "\r\n\r\n".freeze

    # Default timeouts and limits — all overridable via server config hash
    DEFAULTS = {
      header_read_timeout: 10,
      body_read_timeout:   30,
      write_timeout:       10,
      keepalive_timeout:   5,
      max_requests:        100,
      max_header_size:     Request::MAX_HEADER_SIZE,
    }.freeze

    def initialize(socket, app:, logger:, config: {})
      @socket          = socket
      @app             = app      # compiled middleware+router callable
      @logger          = logger
      cfg              = DEFAULTS.merge(config)
      @header_timeout  = cfg[:header_read_timeout]
      @body_timeout    = cfg[:body_read_timeout]
      @write_timeout   = cfg[:write_timeout]
      @ka_timeout      = cfg[:keepalive_timeout]
      @max_requests    = cfg[:max_requests]
      @max_header_size = cfg[:max_header_size]
      @requests_served = 0
      @peer            = @socket.remote_address.inspect_sockaddr rescue 'unknown'
    end

    # Drive the request/response loop until the connection should be closed.
    def run
      loop do
        # First request: use the full header timeout.
        # Subsequent requests on the same connection: use the shorter
        # keepalive idle timeout so we don't hold worker threads too long.
        idle_timeout = @requests_served.zero? ? @header_timeout : @ka_timeout

        result = read_headers(idle_timeout)
        break if result.nil?   # clean EOF, timeout, or parse error

        raw_headers, leftover = result

        req = Request.parse(
          raw_headers,
          socket:        @socket,
          peer:          @peer,
          body_timeout:  @body_timeout,
          socket_buffer: leftover,
        )

        res        = Response.new
        keep_going = dispatch(req, res)

        write_response(res, req)
        @requests_served += 1

        break unless keep_going && persistent?(req, res)
      end
    rescue => e
      # Unexpected error outside the request cycle (e.g., SSL error)
      @logger.error("connection error peer=#{@peer}: #{e.class}: #{e.message}")
    ensure
      # Always close the socket, even if an exception escapes
      @socket.close rescue nil
    end

    private

    # Read from the socket until we have the complete HTTP header block,
    # identified by the \r\n\r\n separator.
    #
    # Returns [header_string, leftover_body_bytes], or nil on EOF/timeout/error.
    #
    # Why return leftover? We read in 4096-byte chunks, so a small POST body
    # may land in the same chunk as the headers. Those bytes must be passed
    # to Request as a pre-buffered "socket_buffer" — otherwise Request would
    # try to read them from the socket again and either block or time out.
    def read_headers(timeout)
      buf      = String.new(encoding: 'BINARY')
      deadline = Time.now + timeout

      loop do
        remaining = deadline - Time.now
        return nil if remaining <= 0   # timeout before headers arrived

        readable = IO.select([@socket], nil, nil, remaining)
        return nil if readable.nil?    # select timed out

        chunk = @socket.read_nonblock(4096, exception: false)
        return nil if chunk.nil?                  # EOF — client disconnected
        next       if chunk == :wait_readable      # spurious wakeup

        buf << chunk

        if buf.bytesize > @max_header_size
          @logger.warn('oversized headers, closing', peer: @peer,
                                                     size: buf.bytesize)
          return nil
        end

        break if buf.include?(CRLF2)
      end

      # Split precisely at the blank line; leftover is body bytes already read.
      head, leftover = buf.split(CRLF2, 2)
      [head, leftover || '']
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
      nil   # client disconnected mid-headers — close silently
    end

    # Run the middleware+router chain. Returns true if the connection can
    # continue (keep-alive), false if it should close after this response.
    def dispatch(req, res)
      @app.call(req, res)
      true
    rescue BadRequest => e
      # Protocol violation — send 400 and close the connection.
      # Closing prevents further requests on a potentially corrupt stream.
      @logger.warn("bad request peer=#{@peer}: #{e.message}")
      res.status = 400
      res.body   = 'Bad Request'
      false
    rescue => e
      req_id = req.id || '-'
      @logger.error("handler error req_id=#{req_id} path=#{req.path}: " \
                    "#{e.class}: #{e.message}")
      res.status = 500
      res.body   = 'Internal Server Error'
      false   # close after 500 to avoid a corrupted response stream
    end

    # Write the serialized response to the socket with a deadline.
    # Uses write_nonblock + IO.select so the worker thread's GVL hold
    # is minimal and slow clients don't block other in-flight requests.
    def write_response(res, req)
      data     = res.to_http(req)
      deadline = Time.now + @write_timeout
      written  = 0

      while written < data.bytesize
        remaining = deadline - Time.now
        if remaining <= 0
          @logger.warn('write timeout', peer: @peer)
          return
        end

        writable = IO.select(nil, [@socket], nil, remaining)
        if writable.nil?
          @logger.warn('write timeout (select)', peer: @peer)
          return
        end

        n = @socket.write_nonblock(data.byteslice(written..), exception: false)
        next if n == :wait_writable
        written += n
      end

      @logger.info(req:, res:, bytes_in: req.bytes_in, bytes_out: data.bytesize)
    rescue Errno::EPIPE, Errno::ECONNRESET
      # Client disconnected before we finished writing — not an error worth logging
    end

    # Determine whether to keep the connection alive for another request.
    def persistent?(req, res)
      return false if @requests_served >= @max_requests
      return false if res.status >= 500   # decided to close in dispatch
      conn = req['connection']&.downcase
      req.http_version == 'HTTP/1.1' ? conn != 'close' : conn == 'keep-alive'
    end
  end
end
