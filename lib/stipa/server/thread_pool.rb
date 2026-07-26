require 'thread'

module Stipa
  # Bounded thread pool with a fixed-depth work queue.
  #
  # Design:
  #   - SizedQueue (stdlib) handles all mutex/condvar complexity.
  #   - Workers loop forever, pulling callables off the queue.
  #   - Shutdown sends one :stop sentinel per worker (poison-pill pattern)
  #     so every thread unblocks from its blocking `pop` and exits cleanly.
  #   - submit returns true/false (never blocks the caller by default).
  #
  # Capacity math:
  #   pool_size=32, queue_depth=64, avg handler=10ms
  #   → steady-state concurrency at 1k req/s = 10 threads (31% utilization)
  #   → 64-slot queue absorbs ~64ms burst before 503s begin
  class ThreadPool
    def initialize(size: 16, queue_depth: nil, on_error: nil)
      @size        = size
      @queue_depth = queue_depth || size * 4
      @on_error    = on_error || method(:default_error_handler)
      @queue       = SizedQueue.new(@queue_depth)
      @workers     = []
      @shutdown    = false
      @mutex       = Mutex.new
      @size.times { @workers << spawn_worker }
    end

    # Submit a job (callable block) to the pool.
    #
    # mode: :drop  — return false immediately if queue is full (default).
    #       :block — spin up to push_timeout seconds before giving up.
    #
    # Returns true if the job was accepted, false if dropped.
    def submit(mode: :drop, push_timeout: 0.5, &job)
      raise ArgumentError, 'job block required' unless job
      return false if @shutdown

      case mode
      when :drop
        # Non-blocking push. SizedQueue raises ThreadError when full.
        begin
          @queue.push(job, true)   # true = non_block
          true
        rescue ThreadError
          false
        end
      when :block
        deadline = Time.now + push_timeout
        loop do
          begin
            @queue.push(job, true)
            return true
          rescue ThreadError
            return false if Time.now >= deadline
            sleep 0.001   # 1ms spin — releases GVL while waiting
          end
        end
      else
        raise ArgumentError, "unknown mode: #{mode.inspect}"
      end
    end

    # Graceful shutdown: stop accepting new jobs, drain the queue,
    # then send a stop sentinel to every worker.
    def shutdown(drain_timeout: 30.0)
      @mutex.synchronize { @shutdown = true }
      deadline = Time.now + drain_timeout
      sleep 0.05 until @queue.empty? || Time.now >= deadline
      # Poison-pill: one :stop per worker so each thread unblocks from pop
      @size.times { @queue.push(:stop) }
      @workers.each { |t| t.join(5) }   # 5s hard join timeout per thread
    end

    def queue_depth; @queue.length; end

    private

    def spawn_worker
      Thread.new do
        loop do
          job = @queue.pop   # blocks until work is available or :stop arrives
          break if job == :stop
          begin
            job.call
          rescue => e
            @on_error.call(e, job)
          end
        end
      end
    end

    def default_error_handler(err, _job)
      warn "[Stipa::ThreadPool] worker error: #{err.class}: #{err.message}"
      err.backtrace&.first(3)&.each { |l| warn "  #{l}" }
    end
  end
end
