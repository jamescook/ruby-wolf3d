# frozen_string_literal: true

# Before anything else, so that plain `rake` works and nobody needs `bundle exec`. It has to
# be the first require in the file: bundler resets the gem list when it sets up, and anything
# activated ahead of it warns about being unresolved on the way past.
require "bundler/setup"

require "rake/testtask"

# This game's own suite. The framework's rake does not know this game exists, and should not: a
# library that names the games built on it is coupled to them. It also could not run this
# usefully — a good part of what it checks needs a copy of Wolfenstein 3D that cannot be
# redistributed, so it would fail on every machine but one.
#
# Nothing here builds the emulator. It is a gem (see the Gemfile) and bundler builds its C
# extension on install, per Ruby ABI — so changing Ruby version gets a rebuild rather than a
# library compiled for another Ruby. There used to be a task here that reached into the
# framework's checkout and ran make, because the emulator was not packaged as a gem and nothing
# else would build it.
Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = false
  t.description = "Run ONE file or test in one process (rake test TEST=test/test_maps.rb) " \
                  "— for the whole suite use rake test:parallel"
end

# The same files split across processes: it shards by each file's recorded time from the
# last run (kept beside this suite, gitignored) and prints one live dot stream.
require_relative "tools/parallel_test"

namespace :test do
  desc "Run this game's suite across processes (rake test:parallel JOBS=8)"
  task :parallel do
    ParallelTest.run(FileList["test/**/test_*.rb"].to_a)
  end
end

desc "Build wolf3d.gba"
task :build do
  ruby "wolf3d.rb"
end

task default: :test
