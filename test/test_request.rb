require 'minitest/autorun'
require_relative '../lib/stipa/request'

# Minitest unit tests for Stipa::Request.
# No server or socket needed — we use a mock socket (StringIO) for body reads.

# A real IO pipe pair used as a socket double.
# IO.select works on pipes (real IO objects), unlike StringIO.
def make_socket(body = '')
  reader, writer = IO.pipe
  writer.write(body)
  writer.close
  reader
end

def make_request(raw_headers, body: '')
  socket = make_socket(body)
  Stipa::Request.parse(
    raw_headers,
    socket: socket,
    peer:   '127.0.0.1:9999',
    body_timeout: 5,
  )
end

class TestRequest < Minitest::Test
  # ── Request-line parsing ─────────────────────────────────────────────────

  def test_parses_get_method_and_path
    req = make_request("GET /hello HTTP/1.1\r\nHost: localhost")
    assert_equal 'GET',    req.method
    assert_equal '/hello', req.path
  end

  def test_parses_post_method
    req = make_request("POST /submit HTTP/1.1\r\nHost: localhost")
    assert_equal 'POST', req.method
  end

  def test_parses_http_version
    req = make_request("GET / HTTP/1.1\r\nHost: localhost")
    assert_equal 'HTTP/1.1', req.http_version
  end

  def test_parses_http_10
    req = make_request("GET / HTTP/1.0\r\nHost: localhost")
    assert_equal 'HTTP/1.0', req.http_version
  end

  # ── Query string ─────────────────────────────────────────────────────────

  def test_separates_path_from_query_string
    req = make_request("GET /search?q=ruby&page=2 HTTP/1.1\r\nHost: localhost")
    assert_equal '/search',    req.path
    assert_equal 'q=ruby&page=2', req.query_string
  end

  def test_empty_query_string_when_no_question_mark
    req = make_request("GET /users HTTP/1.1\r\nHost: localhost")
    assert_equal '', req.query_string
  end

  # ── Headers ──────────────────────────────────────────────────────────────

  def test_parses_headers_case_insensitively
    req = make_request("GET / HTTP/1.1\r\nContent-Type: application/json\r\nHost: localhost")
    assert_equal 'application/json', req.headers['content-type']
    assert_equal 'application/json', req['Content-Type']
    assert_equal 'application/json', req['content-type']
  end

  def test_strips_header_whitespace
    req = make_request("GET / HTTP/1.1\r\nX-Custom:   value with spaces   ")
    assert_equal 'value with spaces', req['x-custom']
  end

  def test_empty_body_when_no_content_length
    req = make_request("GET / HTTP/1.1\r\nHost: localhost")
    assert_equal '', req.body
  end

  # ── Body reading ─────────────────────────────────────────────────────────

  def test_reads_body_by_content_length
    body = 'hello body'
    req  = make_request(
      "POST /echo HTTP/1.1\r\nContent-Length: #{body.bytesize}",
      body: body
    )
    assert_equal body, req.body
  end

  def test_bytes_in_includes_headers_and_body
    headers = "POST /echo HTTP/1.1\r\nContent-Length: 5"
    req     = make_request(headers, body: 'hello')
    assert req.bytes_in >= headers.bytesize + 5
  end

  # ── Error cases ──────────────────────────────────────────────────────────

  def test_raises_bad_request_on_empty_input
    assert_raises(Stipa::BadRequest) { make_request('') }
  end

  def test_raises_bad_request_on_unknown_method
    assert_raises(Stipa::BadRequest) do
      make_request("BREW /coffee HTTP/1.1\r\nHost: localhost")
    end
  end

  def test_raises_bad_request_on_unknown_http_version
    assert_raises(Stipa::BadRequest) do
      make_request("GET / HTTP/2.0\r\nHost: localhost")
    end
  end

  def test_raises_bad_request_on_header_folding
    assert_raises(Stipa::BadRequest) do
      make_request("GET / HTTP/1.1\r\nHost: localhost\r\n continuation")
    end
  end

  def test_raises_bad_request_on_oversized_body
    big_size = Stipa::Request::MAX_BODY_SIZE + 1
    assert_raises(Stipa::BadRequest) do
      make_request(
        "POST / HTTP/1.1\r\nContent-Length: #{big_size}",
        body: 'x'
      )
    end
  end

  # ── Mutable fields ───────────────────────────────────────────────────────

  def test_params_starts_empty
    req = make_request("GET / HTTP/1.1\r\nHost: localhost")
    assert_equal({}, req.params)
  end

  def test_id_starts_nil
    req = make_request("GET / HTTP/1.1\r\nHost: localhost")
    assert_nil req.id
  end

  def test_params_can_be_set
    req = make_request("GET / HTTP/1.1\r\nHost: localhost")
    req.params = { id: '42' }
    assert_equal '42', req.params[:id]
  end
end
