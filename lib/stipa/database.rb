# frozen_string_literal: true

require 'sequel'

module Stipa
  # Database connection manager.
  #
  # Usage:
  #   require 'stipa/database'
  #
  #   Stipa::Database.connect!  # reads DATABASE_URL from environment
  #   DB = Stipa::Database.connection
  #
  # Environment variables:
  #   DATABASE_URL      — connection string (required)
  #   DATABASE_POOL     — max connections (default: 5)
  #
  # Connection string examples:
  #   postgres://user:pass@localhost:5432/myapp
  #   mysql2://user:pass@localhost:3306/myapp
  #   sqlite://db/development.db
  #
  module Database
    module_function

    def connect!
      return @connection if @connection

      @connection = Sequel.connect(
        ENV.fetch('DATABASE_URL'),
        max_connections: Integer(ENV.fetch('DATABASE_POOL', '5')),
        connect_timeout: 5,
        test: true,
        keep_reference: false,
        after_connect: lambda do |connection|
          connection.exec("SET TIME ZONE 'UTC'") if connection.respond_to?(:exec)
        end
      )

      configure_connection!
      @connection
    rescue KeyError => e
      raise "Missing database configuration: #{e.message}"
    rescue ArgumentError => e
      raise "Invalid database configuration: #{e.message}"
    end

    def connection
      @connection || raise('Database.connect! must be called first')
    end

    def connected?
      !@connection.nil?
    end

    def healthy?
      connection.get(Sequel.lit('SELECT 1')) == 1
    rescue Sequel::Error
      false
    end

    def disconnect!
      @connection&.disconnect
      @connection = nil
    end

    def transaction(&block)
      connection.transaction(&block)
    end

    # -------------------------------------------------------------------
    # Database-specific extensions
    # -------------------------------------------------------------------
    #
    # The defaults below are tuned for PostgreSQL. If you're using a
    # different adapter, comment out or remove the lines that don't apply.
    #
    # ── PostgreSQL ──────────────────────────────────────────────────────
    # No changes needed — the lines below work out of the box.
    #
    # ── MySQL / MariaDB ─────────────────────────────────────────────────
    # Replace the body of this method with:
    #
    #   def configure_connection!
    #     return unless @connection.adapter_scheme == :mysql
    #
    #     @connection.extension :pg_json      # not available — remove
    #     @connection.extension :pg_array     # not available — remove
    #
    #     Sequel.extension :pg_json_ops       # not available — remove
    #     Sequel.extension :pg_array_ops      # not available — remove
    #   end
    #
    # ── SQLite ──────────────────────────────────────────────────────────
    # Replace the body of this method with:
    #
    #   def configure_connection!
    #     return unless @connection.adapter_scheme == :sqlite
    #
    #     @connection.extension :pagination   # optional: simple pagination
    #   end
    #
    # ── Generic / adapter-agnostic ──────────────────────────────────────
    # If you want a safe default that works with any adapter:
    #
    #   def configure_connection!
    #     # No adapter-specific extensions.
    #     # Add extensions conditionally based on adapter_scheme:
    #     #
    #     # case @connection.adapter_scheme
    #     # when :postgres
    #     #   @connection.extension :pg_json
    #     #   @connection.extension :pg_array
    #     # when :sqlite
    #     #   @connection.extension :pagination
    #     # end
    #   end
    #
    def configure_connection!
      return unless @connection.adapter_scheme == :postgres

      @connection.extension :pg_json
      @connection.extension :pg_array

      Sequel.extension :pg_json_ops
      Sequel.extension :pg_array_ops
    end

    private_class_method :configure_connection!
  end
end
