# frozen_string_literal: true

# Before anything else, so that plain `rake` works and nobody needs `bundle exec`. It has to
# be the first require in the file: bundler resets the gem list when it sets up, and anything
# activated ahead of it warns about being unresolved on the way past.
require "bundler/setup"

require "rake/testtask"
require "rbconfig"

# THE EMULATOR'S C EXTENSION, WHICH IS NOT OURS AND STILL HAS TO WORK.
#
# A few tests run the built cartridge on a real emulator. That emulator is gemba-core, a C
# extension living inside the FRAMEWORK's checkout — the game only ever sees it as a gem, and
# nothing here would otherwise build it. The framework's own rake rebuilds it when a source
# file is newer than the binary, which is the wrong question: a compiled extension is tied to
# the Ruby it was built against, so switching Ruby versions leaves a binary that is perfectly
# up to date and refuses to load. That is what it looks like when it happens —
#
#   LoadError: linked to incompatible .../libruby.4.0.dylib
#
# — and every emulator-backed test errors at once. So ask the question that actually matters:
# does it LOAD, under the Ruby running right now. If it does not, rebuild it, whatever the
# timestamps say.
#
# The check is a subprocess because a failed load cannot be undone inside this one.
#
# A GAME SHOULD NOT HAVE TO DO THIS. The right home for it is the framework's packaging: an
# extension declared in its gemspec is built at install time and kept per Ruby version, so a
# version change rebuilds instead of loading a binary meant for another Ruby. Until that lands,
# this reaches into the framework's checkout and runs make, which is exactly as rude as it
# sounds. Delete it when the gem builds its own extension.
def gemba_core_dir
  gem_path = Gem.loaded_specs.fetch("ruby-gba").full_gem_path
  File.join(gem_path, "gemba-core")
end

def emulator_loads?
  system(RbConfig.ruby, "-e", 'require "ruby_gba"; RubyGBA::Emulator.load!',
         out: File::NULL, err: File::NULL)
end

desc "Build the emulator's C extension if this Ruby cannot load it"
task :compile_emulator do
  next if emulator_loads?

  puts "The emulator's C extension will not load under this Ruby. Rebuilding it."
  Dir.chdir(gemba_core_dir) { sh "rake", "compile" }
end

# This game's own suite. The framework's rake does not know this game exists, and should not: a
# library that names the games built on it is coupled to them. It also could not run this
# usefully — a good part of what it checks needs a copy of Wolfenstein 3D that cannot be
# redistributed, so it would fail on every machine but one.
Rake::TestTask.new(test: :compile_emulator) do |t|
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
  task parallel: :compile_emulator do
    ParallelTest.run(FileList["test/**/test_*.rb"].to_a)
  end
end

desc "Build wolf3d.gba"
task :build do
  ruby "wolf3d.rb"
end

task default: :test
