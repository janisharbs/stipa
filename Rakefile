require 'rake/testtask'
require 'rubocop/rake_task'

task default: [:test, :rubocop]

desc 'Run all tests'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

desc 'Run RuboCop linter'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.patterns = ['lib/**/*.rb', 'bin/*']
  task.fail_on_corrections = false
end

desc 'Generate YARD documentation'
task :yard do
  require 'yard'
  YARD::Rake::YardocTask.new do |t|
    t.files = ['lib/**/*.rb']
    t.options = ['--no-private']
  end
end

desc 'Build gem'
task :build do
  system 'gem build stipa.gemspec'
end

desc 'Release gem to RubyGems'
task release: [:test, :build] do
  puts 'Gem built successfully! Run: gem push stipa-*.gem'
end

namespace :test do
  desc 'Run a specific test file'
  task :file do
    file = ENV['FILE']
    unless file
      puts 'Usage: rake test:file FILE=test/test_request.rb'
      exit 1
    end
    system "ruby -I lib:test #{file}"
  end
end
