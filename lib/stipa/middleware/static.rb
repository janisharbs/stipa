module Stipa
  module Middleware
    # Serve static files from a directory (typically 'public/').
    #
    # Features:
    #   - Path traversal prevention (no ../../ escaping the root)
    #   - Correct MIME types for web assets including .vue and .mjs files
    #   - ETag-based conditional GET (304 Not Modified)
    #   - HEAD request support
    #   - Only intercepts GET/HEAD; other methods fall through to the app
    #
    # Usage:
    #   app.use Stipa::Middleware::Static, root: 'public'
    #   app.use Stipa::Middleware::Static, root: '/srv/myapp/public', prefix: '/assets'
    class Static
      MIME_TYPES = {
        '.html'  => 'text/html; charset=utf-8',
        '.css'   => 'text/css; charset=utf-8',
        '.js'    => 'application/javascript; charset=utf-8',
        '.mjs'   => 'application/javascript; charset=utf-8',
        # .vue files are served as JS so the browser can import them as ES modules
        '.vue'   => 'application/javascript; charset=utf-8',
        '.json'  => 'application/json; charset=utf-8',
        '.png'   => 'image/png',
        '.jpg'   => 'image/jpeg',
        '.jpeg'  => 'image/jpeg',
        '.gif'   => 'image/gif',
        '.webp'  => 'image/webp',
        '.svg'   => 'image/svg+xml',
        '.ico'   => 'image/x-icon',
        '.woff'  => 'font/woff',
        '.woff2' => 'font/woff2',
        '.ttf'   => 'font/ttf',
        '.eot'   => 'application/vnd.ms-fontobject',
        '.map'   => 'application/json',
        '.txt'   => 'text/plain; charset=utf-8',
        '.xml'   => 'application/xml; charset=utf-8',
      }.freeze

      # root:   directory to serve files from (absolute or relative to cwd)
      # prefix: URL path prefix that triggers static file serving (default '/')
      def initialize(next_app, root:, prefix: '/')
        @next_app = next_app
        @root   = File.expand_path(root)
        @prefix = prefix.chomp('/')
      end

      def call(req, res)
        if %w[GET HEAD].include?(req.method) && req.path.start_with?("#{@prefix}/", @prefix)
          rel = req.path.delete_prefix(@prefix)
          found = serve_static(rel, req, res)
          return found if found
        end
        @next_app.call(req, res)
      end

      private

      def serve_static(rel_path, req, res)
        full_path = File.expand_path(File.join(@root, rel_path))

        # Security: reject any path that escapes the root directory.
        # File.expand_path resolves '..' so this comparison is reliable.
        root_with_sep = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
        return nil unless full_path.start_with?(root_with_sep)
        return nil unless File.file?(full_path)

        stat         = File.stat(full_path)
        etag         = %("stipa-#{stat.mtime.to_i}-#{stat.size}")
        content_type = MIME_TYPES.fetch(File.extname(full_path).downcase, 'application/octet-stream')

        res['ETag']          = etag
        res['Cache-Control'] = 'public, max-age=3600'
        res['Content-Type']  = content_type

        if req['if-none-match'] == etag
          res.status = 304
          res.body   = ''
        elsif req.method == 'HEAD'
          res.status = 200
          res.body   = ''
          res['Content-Length'] = stat.size.to_s
        else
          res.status = 200
          res.body   = File.binread(full_path)
        end

        res
      end
    end
  end
end
