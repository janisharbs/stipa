require 'minitest/autorun'
require_relative '../lib/stipa/version'
require_relative '../lib/stipa/logger'
require_relative '../lib/stipa/middleware'
require_relative '../lib/stipa/request'
require_relative '../lib/stipa/response'
require_relative '../lib/stipa/app'

def make_router_req(method: 'GET', path: '/', version: 'HTTP/1.1')
  raw = "#{method} #{path} #{version}\r\nHost: localhost"
  reader, writer = IO.pipe
  writer.close
  Stipa::Request.parse(raw, socket: reader, peer: '127.0.0.1', body_timeout: 5)
end

# Exercise App#dispatch directly (not through a live server)
class TestRouter < Minitest::Test
  def setup
    @app = Stipa::App.new
    # Access the private dispatch method for unit testing
    @dispatch = @app.method(:dispatch)
  end

  # ── Static string routes ─────────────────────────────────────────────────

  def test_static_get_route_matches
    @app.get('/hello') { |_req, res| res.body = 'hi' }
    req = make_router_req(path: '/hello')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 'hi', res.body
    assert_equal 200,  res.status
  end

  def test_static_post_route_matches
    @app.post('/submit') { |_req, res| res.body = 'submitted' }
    req = make_router_req(method: 'POST', path: '/submit')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 'submitted', res.body
  end

  def test_static_route_returns_404_on_mismatch
    @app.get('/exists') { |_req, res| res.body = 'ok' }
    req = make_router_req(path: '/missing')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 404, res.status
  end

  def test_method_mismatch_returns_404
    @app.get('/only-get') { |_req, res| res.body = 'ok' }
    req = make_router_req(method: 'POST', path: '/only-get')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 404, res.status
  end

  # ── Regexp routes with named captures ────────────────────────────────────

  def test_dynamic_route_sets_params
    @app.get(%r{/users/(?<id>\d+)}) { |req, res| res.body = req.params[:id] }
    req = make_router_req(path: '/users/42')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal '42', res.body
    assert_equal '42', req.params[:id]
  end

  def test_dynamic_route_multi_segment
    @app.get(%r{/orgs/(?<org>[^/]+)/repos/(?<repo>[^/]+)}) do |req, res|
      res.body = "#{req.params[:org]}/#{req.params[:repo]}"
    end
    req = make_router_req(path: '/orgs/ruby/repos/stipa')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 'ruby/stipa', res.body
  end

  def test_regexp_partial_path_does_not_match
    # Route anchored to /users/\d+ should not match /users/abc/extra
    @app.get(%r{\A/users/(?<id>\d+)\z}) { |_req, res| res.body = 'matched' }
    req = make_router_req(path: '/users/99/extra')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 404, res.status
  end

  # ── First-match semantics ─────────────────────────────────────────────────

  def test_first_registered_route_wins
    @app.get('/path') { |_req, res| res.body = 'first' }
    @app.get('/path') { |_req, res| res.body = 'second' }
    req = make_router_req(path: '/path')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 'first', res.body
  end

  # ── 404 message ──────────────────────────────────────────────────────────

  def test_404_body_includes_method_and_path
    req = make_router_req(method: 'DELETE', path: '/ghost')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_includes res.body, 'DELETE'
    assert_includes res.body, '/ghost'
  end

  # ── Response mutation ────────────────────────────────────────────────────

  def test_handler_can_set_status
    @app.get('/created') { |_req, res| res.status = 201; res.body = 'created' }
    req = make_router_req(path: '/created')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_equal 201, res.status
  end

  def test_handler_can_respond_with_json
    @app.get('/data') { |_req, res| res.json(id: 1) }
    req = make_router_req(path: '/data')
    res = Stipa::Response.new
    @dispatch.call(req, res)
    assert_includes res.body, '"id":1'
    assert_equal 'application/json; charset=utf-8', res['content-type']
  end
end
