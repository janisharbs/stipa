require 'minitest/autorun'
require_relative '../lib/stipa/thread_pool'

class TestThreadPool < Minitest::Test
  # ── Basic job execution ───────────────────────────────────────────────────

  def test_executes_submitted_job
    pool    = Stipa::ThreadPool.new(size: 2)
    results = []
    mutex   = Mutex.new

    pool.submit { mutex.synchronize { results << :done } }
    sleep 0.05   # give the worker time to execute

    assert_equal [:done], results
  ensure
    pool.shutdown
  end

  def test_executes_multiple_jobs
    pool    = Stipa::ThreadPool.new(size: 4)
    counter = Mutex.new
    count   = 0

    10.times { pool.submit { counter.synchronize { count += 1 } } }
    sleep 0.1

    assert_equal 10, count
  ensure
    pool.shutdown
  end

  # ── submit return values ──────────────────────────────────────────────────

  def test_submit_returns_true_when_accepted
    pool   = Stipa::ThreadPool.new(size: 2, queue_depth: 10)
    result = pool.submit { sleep 0.001 }
    assert_equal true, result
  ensure
    pool.shutdown
  end

  def test_submit_returns_false_when_queue_full
    # Pool of 1 worker, queue depth of 1.
    # Fill the worker + queue so the next submit overflows.
    pool = Stipa::ThreadPool.new(size: 1, queue_depth: 1)
    latch = Queue.new

    # Block the worker
    pool.submit { latch.pop }
    sleep 0.02   # wait for worker to pick up job

    # Fill the queue
    pool.submit { latch.pop }

    # Now queue is full — next submit should drop
    result = pool.submit(mode: :drop) { nil }
    assert_equal false, result
  ensure
    latch.push(:go) rescue nil
    latch.push(:go) rescue nil
    pool.shutdown(drain_timeout: 1)
  end

  # ── Graceful shutdown ─────────────────────────────────────────────────────

  def test_shutdown_drains_queued_jobs
    pool    = Stipa::ThreadPool.new(size: 2, queue_depth: 20)
    results = Mutex.new
    list    = []

    5.times { |i| pool.submit { results.synchronize { list << i } } }

    pool.shutdown(drain_timeout: 2)

    assert_equal 5, list.size
  end

  def test_submit_returns_false_after_shutdown
    pool = Stipa::ThreadPool.new(size: 1)
    pool.shutdown
    result = pool.submit { nil }
    assert_equal false, result
  end

  # ── Error handling ────────────────────────────────────────────────────────

  def test_worker_error_does_not_stop_pool
    errors  = []
    pool    = Stipa::ThreadPool.new(size: 1, on_error: ->(e, _) { errors << e.message })
    results = []
    mutex   = Mutex.new

    pool.submit { raise 'oops' }
    pool.submit { mutex.synchronize { results << :ok } }
    sleep 0.1

    assert_includes errors, 'oops'
    assert_equal [:ok], results
  ensure
    pool.shutdown
  end
end
