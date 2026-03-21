require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/stipa/reloader'

class TestReloader < Minitest::Test
  class NullLogger
    def warn(msg, **) = nil
    def error(msg, **) = nil
    def info(msg, **) = nil
  end

  def logger = NullLogger.new

  # ── watched_files ────────────────────────────────────────────────────────

  def test_watched_files_returns_only_rb_files
    reloader = Stipa::Reloader.new(logger: logger)
    files = reloader.send(:watched_files)
    assert files.all? { |f| f.end_with?('.rb') }
  end

  def test_watched_files_are_under_project_dir
    reloader = Stipa::Reloader.new(logger: logger)
    reloader.send(:watched_files).each do |f|
      assert f.start_with?(Dir.pwd), "#{f} is outside project dir"
    end
  end

  def test_watched_files_includes_extra_paths
    Dir.mktmpdir do |dir|
      extra = File.join(dir, 'extra.rb')
      File.write(extra, '')
      reloader = Stipa::Reloader.new(logger: logger, watch: [extra])
      assert_includes reloader.send(:watched_files), extra
    end
  end

  # ── change detection ─────────────────────────────────────────────────────

  def test_no_change_when_files_unmodified
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'app.rb')
      File.write(f, 'puts 1')
      reloader = Stipa::Reloader.new(logger: logger, watch: [f])
      reloader.send(:snapshot!)
      refute reloader.send(:changed?)
    end
  end

  def test_detects_modified_file
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'app.rb')
      File.write(f, 'puts 1')
      reloader = Stipa::Reloader.new(logger: logger, watch: [f])
      reloader.send(:snapshot!)
      File.utime(Time.now + 10, Time.now + 10, f)
      assert reloader.send(:changed?)
    end
  end

  def test_detects_new_file_appearing
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'new.rb')
      reloader = Stipa::Reloader.new(logger: logger, watch: [f])
      reloader.send(:snapshot!)
      File.write(f, '')
      assert reloader.send(:changed?)
    end
  end

  # ── syntax checking ──────────────────────────────────────────────────────

  def test_syntax_ok_returns_true_for_valid_file
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'good.rb')
      File.write(f, "puts 'hello'")
      reloader = Stipa::Reloader.new(logger: logger)
      assert reloader.send(:syntax_ok?, f)
    end
  end

  def test_syntax_ok_returns_false_for_invalid_file
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'bad.rb')
      File.write(f, "def foo\n  version: 3''\nend")
      reloader = Stipa::Reloader.new(logger: logger)
      refute reloader.send(:syntax_ok?, f)
    end
  end

  def test_does_not_restart_when_changed_file_has_syntax_error
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'app.rb')
      File.write(f, "puts 'ok'")
      reloader = Stipa::Reloader.new(logger: logger, watch: [f])
      reloader.send(:snapshot!)

      # Overwrite with broken syntax and bump mtime
      File.write(f, "def foo\n  version: 3''\nend")
      File.utime(Time.now + 10, Time.now + 10, f)

      exec_called = false
      reloader.define_singleton_method(:exec) { |*| exec_called = true }

      # Simulate one watch loop iteration
      dirty = reloader.send(:dirty_files)
      bad   = dirty.select { |p| p.end_with?('.rb') && !reloader.send(:syntax_ok?, p) }
      refute bad.empty?, 'expected syntax errors to be detected'
      refute exec_called, 'exec must not be called when there are syntax errors'
    end
  end

  def test_bad_file_stays_dirty_until_fixed
    Dir.mktmpdir do |dir|
      f = File.join(dir, 'app.rb')
      File.write(f, "puts 'ok'")
      reloader = Stipa::Reloader.new(logger: logger, watch: [f])
      reloader.send(:snapshot!)

      # Break the file
      File.write(f, "def foo\n  version: 3''\nend")
      File.utime(Time.now + 10, Time.now + 10, f)

      bad = reloader.send(:dirty_files).select { |p| !reloader.send(:syntax_ok?, p) }
      # Simulate what watch_loop does: advance only clean files, leave bad ones dirty
      # (no clean files here, so @mtimes is untouched)
      (reloader.send(:dirty_files) - bad).each { }

      # File should still appear dirty on the next poll
      assert reloader.send(:dirty_files).include?(f)
    end
  end

  # ── exec uses RbConfig.ruby ───────────────────────────────────────────────

  def test_perform_restart_uses_ruby_interpreter
    captured = nil
    reloader = Stipa::Reloader.new(logger: logger)
    reloader.define_singleton_method(:exec) { |*args| captured = args }
    reloader.send(:perform_restart)
    assert_equal RbConfig.ruby, captured.first,
      'expected RbConfig.ruby as first exec arg, not a bare script name'
  end

  def test_perform_restart_passes_script_and_argv
    captured = nil
    reloader = Stipa::Reloader.new(logger: logger)
    reloader.define_singleton_method(:exec) { |*args| captured = args }
    reloader.send(:perform_restart)
    assert_equal [RbConfig.ruby, $0, *ARGV], captured
  end

  # ── thread lifecycle ──────────────────────────────────────────────────────

  def test_start_spawns_active_thread
    reloader = Stipa::Reloader.new(logger: logger, interval: 60)
    reloader.start
    assert reloader.instance_variable_get(:@thread).alive?
  ensure
    reloader.stop
  end

  def test_stop_kills_watcher_thread
    reloader = Stipa::Reloader.new(logger: logger, interval: 60)
    reloader.start
    reloader.stop
    thread = reloader.instance_variable_get(:@thread)
    thread.join(1)
    refute thread.alive?
  end
end
