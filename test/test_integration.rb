require 'minitest/autorun'
require 'net/http'
require 'json'
require_relative '../lib/stipa'

# Integration test: starts a real Stipa server in a background thread,
# makes live HTTP requests via Net::HTTP, and asserts on the responses.
#
# Run: ruby test/test_integration.rb
#
# Each test class uses a different port to avoid conflicts when running
# tests concurrently or if a previous run left a socket in TIME_WAIT.

class TestIntegration < Minitest::Test
  PORT = 19_876

  def setup
    @app = Stipa::App.new
    @app.use Stipa::Middleware::RequestId
    @app.use Stipa::Middleware::Timing

    @app.get('/')       { |_req, res| res.body = 'root' }
    @app.get('/hello')  { |_req, res| res.body = 'Hello, world!' }
    @app.get('/health') { |_req, res| res.json(status: 'ok') }
    @app.post('/echo')  { |req, res|  res.body = req.body }
    @app.get(%r{/users/(?<id>\d+)}) { |req, res| res.json(id: req.params[:id].to_i) }

    # Start server in background thread; use pool_size: 4 for fast test startup
    @thread = Thread.new do
      @app.start(host: '127.0.0.1', port: PORT, pool_size: 4, log_level: :error)
    end

    # Wait for the server to bind
    deadline = Time.now + 3
    begin
      TCPSocket.new('127.0.0.1', PORT).close
    rescue Errno::ECONNREFUSED
      sleep 0.05
      retry if Time.now < deadline
      raise 'server did not start in time'
    end
  end

  def teardown
    @thread.kill
    @thread.join(1)
  end

  # ── Basic routing ────────────────────────────────────────────────────────

  def test_get_root
    res = get('/')
    assert_equal '200', res.code
    assert_equal 'root', res.body
  end

  def test_get_hello
    res = get('/hello')
    assert_equal '200', res.code
    assert_equal 'Hello, world!', res.body
  end

  def test_get_missing_returns_404
    res = get('/nope')
    assert_equal '404', res.code
  end

  # ── JSON response ────────────────────────────────────────────────────────

  def test_json_response
    res = get('/health')
    assert_equal '200',              res.code
    assert_includes res['content-type'], 'application/json'
    data = JSON.parse(res.body)
    assert_equal 'ok', data['status']
  end

  # ── Dynamic route ────────────────────────────────────────────────────────

  def test_dynamic_param_extraction
    res  = get('/users/42')
    data = JSON.parse(res.body)
    assert_equal 42, data['id']
  end

  # ── POST with body ───────────────────────────────────────────────────────

  def test_post_echo
    res = post('/echo', 'ping body')
    assert_equal '200',      res.code
    assert_equal 'ping body', res.body
  end

  # ── Middleware headers ───────────────────────────────────────────────────

  def test_request_id_header_present
    res = get('/hello')
    refute_nil res['x-request-id'], 'X-Request-Id header should be present'
    assert_match(/\A[0-9a-f]{16}\z/, res['x-request-id'])
  end

  def test_timing_header_present
    res = get('/hello')
    refute_nil res['x-response-time'], 'X-Response-Time header should be present'
    assert_match(/\d+\.\d+ms/, res['x-response-time'])
  end

  # ── Keep-alive ───────────────────────────────────────────────────────────

  def test_http11_keep_alive_by_default
    res = get('/hello')
    assert_equal 'keep-alive', res['connection']
  end

  def test_multiple_requests_on_same_connection
    Net::HTTP.start('127.0.0.1', PORT) do |http|
      r1 = http.get('/hello')
      r2 = http.get('/health')
      assert_equal '200', r1.code
      assert_equal '200', r2.code
    end
  end

  private

  def get(path)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{PORT}#{path}"))
  end

  def post(path, body)
    uri = URI("http://127.0.0.1:#{PORT}#{path}")
    Net::HTTP.post(uri, body, 'Content-Type' => 'text/plain')
  end
end
