module Stipa
  # Development file watcher that restarts the process when Ruby source files change.
  #
  # Enabled when:
  #   - STIPA_RELOAD=1 environment variable is set, OR
  #   - reload: true is passed to App#start / Server#start
  #
  # Strategy:
  #   A background thread polls the mtime of all .rb files visible to Ruby
  #   ($LOADED_FEATURES) plus any extra watch paths supplied by the user.
  #   When a change is detected it calls exec($0, *ARGV) which replaces the
  #   current process image with a fresh one — same PID namespace, same
  #   command line arguments, all changes picked up from scratch.
  #
  # Why exec instead of in-process reload:
  #   In-process reload requires clearing constants, unloading files, and
  #   rebuilding the route table. exec is simpler, safer, and handles any
  #   kind of change (routes, middleware, config, gems) without edge cases.
  class Reloader
    DEFAULT_INTERVAL = 0.5 # seconds between polls

    def initialize(logger:, interval: DEFAULT_INTERVAL, watch: [])
      @logger   = logger
      @interval = interval
      @extra    = Array(watch).map { |p| File.expand_path(p) }
      @mtimes   = {}
      @thread   = nil
    end

    def start
      snapshot!
      @thread = Thread.new { watch_loop }
      @thread.name = 'stipa-reloader'
      @thread.abort_on_exception = false
      @logger.warn('reloader active — watching for file changes')
    end

    def stop
      @thread&.kill
    end

    private

    def watch_loop
      loop do
        sleep @interval
        dirty = dirty_files
        next if dirty.empty?

        bad = dirty.select { |f| f.end_with?('.rb') && !syntax_ok?(f) }
        if bad.any?
          bad.each { |f| @logger.warn("syntax error in #{f} — fix and save to restart") }
          # Advance mtime only for clean files so bad ones stay dirty until fixed
          (dirty - bad).each { |f| @mtimes[f] = mtime(f) }
        else
          dirty.each { |f| @mtimes[f] = mtime(f) }
          @logger.warn('file change detected — restarting')
          $stdout.flush
          $stderr.flush
          perform_restart
        end
      end
    rescue => e
      @logger.error("reloader crashed: #{e.class}: #{e.message}")
    end

    # Watch only .rb files under the project root (Dir.pwd), plus any extra
    # paths the user supplied. Avoids polling hundreds of gem files.
    def watched_files
      project_files = Dir.glob(File.join(Dir.pwd, '**', '*.rb'))
      (project_files + @extra).uniq
    end

    def snapshot!
      watched_files.each do |path|
        @mtimes[path] = mtime(path)
      end
    end

    # Returns files whose mtime has changed since the last snapshot, without
    # updating @mtimes (callers decide when to advance the snapshot).
    def dirty_files
      watched_files.select { |path| mtime(path) != @mtimes[path] }
    end

    # Kept for backwards compatibility with tests / external callers.
    def changed?
      dirty = dirty_files
      dirty.each { |f| @mtimes[f] = mtime(f) }
      dirty.any?
    end

    def syntax_ok?(path)
      system(RbConfig.ruby, '-c', path, out: File::NULL, err: File::NULL)
    end

    def perform_restart
      exec(RbConfig.ruby, $0, *ARGV)
    end

    def mtime(path)
      File.mtime(path)
    rescue Errno::ENOENT
      nil
    end
  end
end
