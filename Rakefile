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
# library compiled for another Ruby.
#
# THE SUITE RUNS IN RACTORS — Ruby's way of using every core inside one process — through the
# minitest-ractor plugin, the way the framework's own suite runs. A worker is refused the moment
# it touches state another one can see, so a green run also says the code these tests reached
# keeps none. `--no-ractor` in TESTOPTS runs it the ordinary way, for chasing one failure.
#
# --ractor GOES INTO TESTOPTS rather than the task's own options, because rake reads TESTOPTS
# INSTEAD of those options when it is set — so `TESTOPTS=--verbose` would quietly run the whole
# suite without Ractors, and a test could pass there that the suite would refuse. The flag is
# matched as a whole word, so a pattern that happens to say "ractor" is not taken for it.
testopts = ENV.fetch("TESTOPTS", "")
ENV["TESTOPTS"] = "--ractor #{testopts}".strip unless testopts.split.intersect?(%w[--ractor --no-ractor])

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = false
  t.description = 'Run the suite (one file with TEST=test/test_maps.rb, one test with ' \
                  'TESTOPTS="--name=/pattern/")'
end

desc "Build wolf3d.gba"
task :build do
  ruby "wolf3d.rb"
end

namespace :build do
  # NOT the game's frames. This samples the BUILD — Ruby, on this machine, turning your copy of
  # Wolfenstein into a cartridge. Where the finished cartridge spends its 228 scanlines a frame
  # is a different question, and the framework's own rom.profile answers that one.
  desc "Where the BUILD's time goes: sample a full build, for speedscope.org"
  task :profile do
    ruby "tools/profile_build.rb"
  end
end

task default: :test
