# lib/stipa.rb — single require entry point
#
# Load order follows the dependency graph: leaf modules first,
# composite modules last. Adding `require 'stipa'` to a user's file
# loads the entire framework.
#
# Dependency order:
#   version      — no deps
#   logger       — no deps
#   thread_pool  — no deps
#   middleware   — no deps
#   static       — depends on middleware
#   template     — no deps (stdlib only: erb, json)
#   request      — no deps
#   response     — depends on template (via render helper)
#   connection   — depends on request, response
#   server       — depends on thread_pool, connection
#   app          — depends on server, middleware, template, request, response

require_relative 'stipa/version'
require_relative 'stipa/logger'
require_relative 'stipa/thread_pool'
require_relative 'stipa/reloader'
require_relative 'stipa/middleware'
require_relative 'stipa/static'
require_relative 'stipa/template'
require_relative 'stipa/request'
require_relative 'stipa/response'
require_relative 'stipa/connection'
require_relative 'stipa/server'
require_relative 'stipa/app'
