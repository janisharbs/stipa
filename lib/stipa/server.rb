require 'socket'
require_relative 'thread_pool'
require_relative 'connection'
require_relative 'request'
require_relative 'response'
require_relative 'logger'

module Stipa
  # TCP accept loop and connection lifecycle manager.
  #
  # Architecture:
  #
  #   Main thread (accept loop)          Worker threads (pool)
  #   ─────────────────────────          ──────────────────────────────────
  #   TCPServer.accept_nonblock            Connection.new(socket, ...).run
  #     └─> pool.submit(job)   ─────>        └─> Request.parse
  #           (drop → 503)                    └─> app.call(req, res)
  #           (accept continues)              └─> write_response
  #
  # Socket options:
  #   SO_REUSEADDR  — always set; allows rebinding immediately after SIGTERM
  #                   without waiting for the TIME_WAIT timeout (~60 s).
  #   SO_REUSEPORT  — set on Linux ≥ 3.9 when available; multiple processes
  #                   can bind the same port simultaneously, enabling zero-
  #                   downtime rolling restarts via a process supervisor.
  #   TCP_NODELAY   — disables Nagle's algorithm; reduces latency for small
  #                   responses (JSON APIs) by sending immediately rather than
  #                   waiting to coalesce small writes.
  #   listen(1024)  — kernel-level SYN backlog; OSes cap at net.core.somaxconn.
  #
  # Backpressure (when all workers are busy and the queue is full):
  #   We write a 503 directly on the accept thread without involving a worker.
  #   This keeps the accept loop free to continue processing new connections
  #   and avoids wasting a worker thread on a connection we'll immediately reject.
  #
  # Graceful shutdown (SIGTERM / SIGINT):
  #   1. @running = false → accept loop exits after the current poll returns
  #   2. pool.shutdown(drain_timeout:) → waits for in-flight requests to finish
  #   3. server socket is closed in the ensure block of start
  class Server
    DEFAULT_CONFIG = {
      host:                '0.0.0.0',
      port:                3710,
      pool_size:           32,
      queue_depth:         64,
      drain_timeout:       30,
      header_read_timeout: 10,
      body_read_timeout:   30,
      write_timeout:       10,
      keepalive_timeout:   5,
      max_requests:        100,
      max_header_size:     8 * 1024,
      max_body_size:       1 * 1024 * 1024,
      backpressure:        :drop,   # :drop (503) or :block (wait briefly)
      log_level:           :info,
    }.freeze

    def initialize(app:, **overrides)
      @app    = app   # compiled middleware+router callable
      @config = DEFAULT_CONFIG.merge(overrides)
      @logger = Logger.new(level: @config[:log_level])
      @pool   = ThreadPool.new(
        size:        @config[:pool_size],
        queue_depth: @config[:queue_depth],
        on_error:    method(:pool_error),
      )
      @running = false
    end

    # Start the server. Blocks until SIGTERM/SIGINT.
    def start
      @server  = build_server_socket
      @running = true

      register_signals

      @logger.info(
        req: nil, res: nil,
        msg: 'Stīpa listening',
        host: @config[:host],
        port: @config[:port],
        workers: @config[:pool_size],
        queue: @config[:queue_depth],
      )

      accept_loop
    ensure
      @server&.close rescue nil
      @logger.info(req: nil, res: nil, msg: 'Stīpa stopped')
    end

    private

    def accept_loop
      while @running
        begin
          # accept_nonblock raises IO::WaitReadable when no connection is
          # waiting. We use IO.select to poll every 100ms so @running is
          # checked regularly for clean shutdown.
          socket = @server.accept_nonblock
        rescue IO::WaitReadable
          IO.select([@server], nil, nil, 0.1)
          retry
        rescue Errno::ECONNABORTED, Errno::EPROTO
          # Connection was aborted between SYN and accept — ignore and continue
          retry
        rescue IOError, Errno::EBADF
          # Server socket was closed (shutdown path) — exit the loop
          break
        end

        configure_client(socket)
        enqueue_or_503(socket)
      end
    end

    # Try to hand the socket to the thread pool. If the queue is full,
    # write a 503 directly on the accept thread and close the socket.
    def enqueue_or_503(socket)
      submitted = @pool.submit(mode: @config[:backpressure]) do
        Connection.new(
          socket,
          app:    @app,
          logger: @logger,
          config: @config,
        ).run
      end

      return if submitted

      # Queue is full — fast reject
      @logger.warn('backpressure 503', queue_depth: @pool.queue_depth)
      begin
        socket.write(
          "HTTP/1.1 503 Service Unavailable\r\n" \
          "Content-Type: text/plain\r\n" \
          "Content-Length: 19\r\n" \
          "Connection: close\r\n" \
          "\r\n" \
          "Service Unavailable"
        )
      rescue nil
      ensure
        socket.close rescue nil
      end
    end

    def build_server_socket
      server = TCPServer.new(@config[:host], @config[:port])

      # SO_REUSEADDR: rebind immediately after SIGTERM without TIME_WAIT delay
      server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

      # SO_REUSEPORT (Linux ≥ 3.9): allows multiple processes on the same port
      # for zero-downtime rolling restarts. Guard with const_defined? for
      # portability across macOS, BSD, and older Linux kernels.
      if Socket.const_defined?(:SO_REUSEPORT)
        server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true)
      end

      # Backlog of 1024: kernel queues up to this many SYN_RCVD connections.
      # The actual limit is min(1024, net.core.somaxconn) on Linux.
      server.listen(1024)
      server
    end

    def configure_client(socket)
      # TCP_NODELAY disables Nagle's algorithm so small responses
      # (e.g., a 200-byte JSON body) are sent in one TCP segment
      # rather than waiting 40–200ms for more data to coalesce.
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
    rescue StandardError
      # Not fatal — continue without TCP_NODELAY
    end

    def register_signals
      shutdown_proc = ->(_signal) {
        @logger.warn('shutdown signal received')
        @running = false
        @pool.shutdown(drain_timeout: @config[:drain_timeout])
      }
      trap('TERM', &shutdown_proc)
      trap('INT',  &shutdown_proc)
    end

    def pool_error(err, _job)
      @logger.error("worker crash: #{err.class}: #{err.message}")
    end
  end
end
