# lib/stipa.rb — single require entry point
#
# Load order follows the dependency graph: leaf modules first,
# composite modules last. Adding `require 'stipa'` to a user's file
# loads the entire framework.
#
# Dependency order:
#   version                    — no deps
#   logger                     — no deps
#   server/thread_pool         — no deps
#   server/reloader            — no deps
#   middleware/stack            — no deps
#   middleware/static           — depends on middleware/stack
#   template/template           — no deps (stdlib only: erb, json)
#   http/request                — no deps
#   http/response               — depends on template (via render helper)
#   http/connection             — depends on http/request, http/response
#   server/server               — depends on server/thread_pool, http/connection
#   app                         — depends on server/server, middleware, template, http/request, http/response

require_relative 'stipa/version'
require_relative 'stipa/logger'
require_relative 'stipa/server/thread_pool'
require_relative 'stipa/server/reloader'
require_relative 'stipa/middleware/stack'
require_relative 'stipa/middleware/static'
require_relative 'stipa/template/template'
require_relative 'stipa/http/request'
require_relative 'stipa/http/response'
require_relative 'stipa/http/connection'
require_relative 'stipa/server/server'
require_relative 'stipa/app'
