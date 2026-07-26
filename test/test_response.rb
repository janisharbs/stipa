require 'minitest/autorun'
require_relative '../lib/stipa/version'
require_relative '../lib/stipa/http/request'
require_relative '../lib/stipa/http/response'

def make_response_req(line = "GET / HTTP/1.1\r\nHost: localhost")
  reader, writer = IO.pipe
  writer.close
  Stipa::Request.parse(line, socket: reader, peer: '127.0.0.1', body_timeout: 5)
end

class TestResponse < Minitest::Test
  # ── Status line ──────────────────────────────────────────────────────────

  def test_default_status_200
    res = Stipa::Response.new
    assert_includes res.to_http, 'HTTP/1.1 200 OK'
  end

  def test_404_status_line
    res = Stipa::Response.new
    res.status = 404
    assert_includes res.to_http, 'HTTP/1.1 404 Not Found'
  end

  def test_500_status_line
    res = Stipa::Response.new
    res.status = 500
    assert_includes res.to_http, 'HTTP/1.1 500 Internal Server Error'
  end

  # ── Content-Length ───────────────────────────────────────────────────────

  def test_content_length_matches_body
    res      = Stipa::Response.new
    res.body = 'Hello!'
    wire     = res.to_http
    assert_includes wire, 'Content-Length: 6'
    assert_includes wire, 'Hello!'
  end

  def test_content_length_uses_bytesize_not_char_count
    # UTF-8: "é" is 1 char but 2 bytes
    res      = Stipa::Response.new
    res.body = "caf\xC3\xA9".b   # "café" as binary
    wire     = res.to_http
    assert_includes wire, "Content-Length: 5"
  end

  def test_empty_body_has_zero_content_length
    res  = Stipa::Response.new
    wire = res.to_http
    assert_includes wire, 'Content-Length: 0'
  end

  # ── Headers ──────────────────────────────────────────────────────────────

  def test_default_content_type_is_text_plain
    res  = Stipa::Response.new
    wire = res.to_http
    assert_includes wire, 'Content-Type: text/plain; charset=utf-8'
  end

  def test_set_header_titlecases_name
    res = Stipa::Response.new
    res.set_header('content-type', 'text/html')
    assert_equal 'text/html', res['content-type']
    assert_includes res.to_http, 'Content-Type: text/html'
  end

  def test_date_header_is_present
    res  = Stipa::Response.new
    wire = res.to_http
    assert_includes wire, 'Date: '
  end

  def test_server_header_contains_version
    res  = Stipa::Response.new
    wire = res.to_http
    assert_includes wire, "Server: Stipa/#{Stipa::VERSION}"
  end

  # ── JSON helper ──────────────────────────────────────────────────────────

  def test_json_sets_content_type
    res = Stipa::Response.new
    res.json(id: 1, name: 'Alice')
    wire = res.to_http
    assert_includes wire, 'Content-Type: application/json; charset=utf-8'
    assert_includes wire, '{"id":1,"name":"Alice"}'
  end

  def test_json_returns_self_for_chaining
    res    = Stipa::Response.new
    result = res.json(ok: true)
    assert_same res, result
  end

  # ── Keep-alive headers ───────────────────────────────────────────────────

  def test_http11_default_keep_alive
    req  = make_response_req("GET / HTTP/1.1\r\nHost: localhost")
    res  = Stipa::Response.new
    wire = res.to_http(req)
    assert_includes wire, 'Connection: keep-alive'
    assert_includes wire, 'Keep-Alive: timeout=5, max=100'
  end

  def test_http11_connection_close_request
    req = make_response_req("GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close")
    res  = Stipa::Response.new
    wire = res.to_http(req)
    assert_includes wire, 'Connection: close'
    refute_includes wire, 'Keep-Alive:'
  end

  def test_http10_default_close
    req = make_response_req("GET / HTTP/1.0\r\nHost: localhost")
    res  = Stipa::Response.new
    wire = res.to_http(req)
    assert_includes wire, 'Connection: close'
  end

  def test_500_always_closes
    req  = make_response_req("GET / HTTP/1.1\r\nHost: localhost")
    res  = Stipa::Response.new
    res.status = 500
    wire = res.to_http(req)
    assert_includes wire, 'Connection: close'
  end

  # ── Wire format ──────────────────────────────────────────────────────────

  def test_blank_line_between_headers_and_body
    res      = Stipa::Response.new
    res.body = 'test'
    wire     = res.to_http
    assert_includes wire, "\r\n\r\ntest"
  end

  def test_to_http_without_req_omits_connection_header
    res  = Stipa::Response.new
    wire = res.to_http   # no req argument
    refute_includes wire, 'Connection:'
  end
end
