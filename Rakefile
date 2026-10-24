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

# The WOLF3D_* dials that are set, as --set arguments for the framework's own `ruby-gba` command.
# wolf3d.rb reads the environment only when it is the file run, and under `ruby-gba` it is not, so
# the dials have to be handed over. Loading the library to learn their names costs a second, and
# keeps one list of them.
def dial_arguments
  require_relative "lib/wolf3d"
  settings = Wolf3D.settings_from(ENV).map { |name, value| "#{name}=#{value}" }
  settings.empty? ? [] : ["--set", *settings]
end

namespace :build do
  # The same game as a program for this computer: a window, with the keyboard as the console's
  # buttons (mGBA's keys). The framework builds it — `ruby-gba build --format=native`.
  desc "Build wolf3d-desktop, the game as a desktop app (the WOLF3D_* dials work as for build)"
  task :desktop do
    sh "bundle", "exec", "ruby-gba", "build", "wolf3d.rb", "--format=native", "--output=wolf3d-desktop",
       *dial_arguments
  end

  # The same program for another computer, built on this one: the framework cross-compiles with
  # zig, so any machine can make all three. There is no Mac among them because the framework offers
  # no Mac target — a Mac program is built on a Mac, by plain build:desktop. The Windows one has
  # been played on Windows, in a virtual machine; the two Linux ones have not been run on Linux.
  namespace :desktop do
    { windows: "wolf3d-windows-desktop.exe", linux: "wolf3d-linux-desktop",
      linux_arm: "wolf3d-linux-arm-desktop" }.each do |name, output|
      target = name.to_s.tr("_", "-")
      desc "Build #{output}, the desktop app for #{target} (the WOLF3D_* dials work as for build)"
      task name do
        sh "bundle", "exec", "ruby-gba", "build", "wolf3d.rb", "--format=native", "--target=#{target}",
           "--output=#{output}", *dial_arguments
      end
    end
  end

  # The CARTRIDGE's frames, through `ruby-gba profile`: what the build made of each routine and
  # which ones fit in the console's quick memory, then the game run in the emulator and where its
  # frames went. OPTS goes to that command as it is, so its own options need no list here —
  # `ruby-gba help profile` has them. Left alone it measures the game as it boots, which is the
  # menu, so name the scene; and a player standing still costs little, so hold something:
  #
  #   rake build:gba_profile WOLF3D_FLOORS=1 OPTS="--scene playing --keys up"
  desc 'Where the CARTRIDGE\'s frames go, run in the emulator (OPTS="--scene playing --keys up" ' \
       "passes ruby-gba profile options)"
  task :gba_profile do
    sh "bundle", "exec", "ruby-gba", "profile", "wolf3d.rb", *dial_arguments, *ENV.fetch("OPTS", "").split
  end

  # NOT the game's frames. This samples the BUILD — Ruby, on this machine, turning your copy of
  # Wolfenstein into a cartridge. Where the finished cartridge spends its 228 scanlines a frame
  # is a different question, and build:gba_profile answers that one.
  desc "Where the BUILD's time goes: sample a full build, for speedscope.app"
  task :profile do
    ruby "tools/profile_build.rb"
  end
end

task default: :test
