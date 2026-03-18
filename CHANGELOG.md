# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
