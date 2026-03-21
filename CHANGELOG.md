# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2026-03-20

### Added

- **Hot reload** (`STIPA_RELOAD=1`) — background thread watches project `.rb` files and
  restarts the process via `exec` when a change is detected
- **Syntax guard** — if a changed file has a syntax error, the reloader logs the
  problem and keeps watching; it will not restart until the error is fixed, preventing
  the process from dying on a bad save
- **`.gitignore` generation** — `stipa new` now writes a `.gitignore` covering Ruby,
  Node/npm, OS artefacts, and Vue build output
- **Automatic git init** — `stipa new` runs `git init && git add . && git commit` after
  scaffolding so the project starts with a clean history
- **`interface Window { _t0?: number }`** added to the generated `shims-vue.d.ts`

### Fixed

- **CORS header injection** — `Middleware::Cors` no longer reflects an arbitrary
  `Origin` request header. Wildcard config sends the literal `*`; an explicit allowlist
  only echoes origins that are in the list
- **`instance_variable_set` removed** — the generated `MethodOverride` middleware now
  uses the public `req.method =` setter instead of reaching into private state
- **Shell-form `system()` calls** — all internal `git` invocations in the generator now
  use array form (`system('git', 'init', '-q')`) so no shell is spawned and there is no
  injection surface
- **Default bind address changed from `0.0.0.0` to `127.0.0.1`** — the server and
  generated templates now bind localhost-only by default; pass `host: '0.0.0.0'` to
  expose on all interfaces
- **`BadRequest` details no longer sent to the client** — the error message is logged
  server-side; the response body is now the generic string `'Bad Request'`

## [0.1.0] - 2024-03-18

### Added

- Initial release of Stīpa framework
- Zero-dependency HTTP/1.1 server built on Ruby stdlib
- Thread pool with bounded queue and graceful shutdown
- Middleware stack with built-in RequestId, Timing, CORS, and Static middleware
- ERB template engine with layout support and Vue 3 island helpers
- Vue.js integration for interactive components
- CLI generator for scaffolding MVC and API-only applications
- Comprehensive routing with named captures support
- Keep-alive connections with configurable timeouts
- Socket optimization (SO_REUSEPORT, TCP_NODELAY)

### Features

- **HTTP/1.1 Protocol**: Full HTTP/1.1 support with keep-alive
- **Threading**: Configurable thread pool with graceful shutdown
- **Middleware**: Pre-compiled middleware stack for zero per-request overhead
- **Templates**: ERB-based views with partials and layouts
- **Vue.js**: Island architecture for interactive components
- **CLI**: `stipa new` command for project generation
- **Production Ready**: Socket tuning, backpressure handling, structured logging
