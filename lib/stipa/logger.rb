require 'monitor'

module Stipa
  # Structured, leveled logger that writes one logfmt line per event.
  #
  # Format (parseable by Splunk, Datadog, Loki, grep):
  #   time=2026-03-18T12:00:00.123Z level=INFO req_id=a1b2c3d4 method=GET
  #   path=/users status=200 bytes_in=0 bytes_out=412
  #
  # Thread-safe via Monitor (reentrant mutex — safe when a log call
  # triggers another log call from a rescue block in the same thread).
  class Logger
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    def initialize(output: $stdout, level: :info)
      @output = output
      @level  = LEVELS.fetch(level, 1)
      @lock   = Monitor.new
    end

    # Log a completed request/response cycle. Called by Connection.
    def info(req: nil, res: nil, bytes_in: 0, bytes_out: 0, **extra)
      return if @level > LEVELS[:info]
      fields = {
        time:      utc_now,
        level:     'INFO',
        req_id:    req&.id    || '-',
        method:    req&.method || '-',
        path:      req&.path   || '-',
        status:    res&.status || '-',
        bytes_in:  bytes_in,
        bytes_out: bytes_out,
      }.merge(extra)
      write(logfmt(fields))
    end

    def warn(msg, **fields);  log(:warn,  msg, **fields); end
    def error(msg, **fields); log(:error, msg, **fields); end
    def debug(msg, **fields); log(:debug, msg, **fields); end

    private

    def log(level, msg, **fields)
      return if @level > LEVELS[level]
      write(logfmt({ time: utc_now, level: level.to_s.upcase, msg: msg }.merge(fields)))
    end

    def write(line)
      @lock.synchronize { @output.puts(line) }
    end

    # Encode as logfmt: key=value pairs, quoting values with special chars.
    def logfmt(fields)
      fields.map do |k, v|
        v_s = v.to_s
        v_s = %("#{v_s.gsub('"', '\\"')}") if v_s.match?(/[ ="\\]/)
        "#{k}=#{v_s}"
      end.join(' ')
    end

    def utc_now
      Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
    end
  end
end
