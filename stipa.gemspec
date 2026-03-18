lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'stipa/version'

Gem::Specification.new do |spec|
  spec.name          = 'stipa'
  spec.version       = Stipa::VERSION
  spec.authors       = ['Pedro Harbs']
  spec.email         = ['harbspj@gmail.com']
  spec.homepage      = 'https://github.com/pedroharbs/stipa'
  spec.license       = 'MIT'

  spec.summary       = 'Minimal, production-ready HTTP framework for Ruby'
  spec.description   = <<~DESC
    Stīpa is a lightweight, zero-dependency HTTP/1.1 framework built entirely on Ruby stdlib.

    Features:
    - Pure stdlib (socket, thread, erb, json, securerandom)
    - HTTP/1.1 with keep-alive, SO_REUSEPORT, and TCP_NODELAY
    - Thread pool with bounded queue and graceful shutdown
    - Pre-compiled middleware stack with zero per-request overhead
    - ERB templates with layouts, partials, and Vue 3 island helpers
    - CLI generator for MVC and API-only applications
    - Structured logging in logfmt format
    - Named route parameters via regex captures
  DESC

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir.glob(%w[
    bin/*
    lib/**/*.rb
    lib/js/**/*
    media/*
    LICENSE
    README.md
    CHANGELOG.md
  ])

  spec.bindir        = 'bin'
  spec.executables   = ['stipa']
  spec.require_paths = ['lib']

  spec.metadata = {
    'bug_tracker_uri'       => 'https://github.com/pedroharbs/stipa/issues',
    'changelog_uri'         => 'https://github.com/pedroharbs/stipa/releases',
    'documentation_uri'     => 'https://github.com/pedroharbs/stipa',
    'homepage_uri'          => 'https://github.com/pedroharbs/stipa',
    'source_code_uri'       => 'https://github.com/pedroharbs/stipa',
    'rubygems_mfa_required' => 'true'
  }

  spec.add_development_dependency 'minitest', '~> 5.20'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'yard', '~> 0.9'

  spec.post_install_message = <<~MESSAGE
    ╔══════════════════════════════════════════════════════════════════════════╗
    ║                                                                          ║
    ║                 Welcome to Stīpa! 🚀                                    ║
    ║                                                                          ║
    ║  Minimal, production-ready HTTP framework for Ruby with zero deps.     ║
    ║                                                                          ║
    ║  Get started:                                                           ║
    ║    $ stipa new my_app                                                   ║
    ║    $ cd my_app && bundle install && npm install                        ║
    ║    $ bundle exec ruby server.rb                                        ║
    ║                                                                          ║
    ║  Documentation: https://github.com/pedroharbs/stipa                   ║
    ║                                                                          ║
    ╚══════════════════════════════════════════════════════════════════════════╝
  MESSAGE
end
