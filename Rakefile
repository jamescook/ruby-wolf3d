# frozen_string_literal: true

# Before anything else, so that plain `rake` works and nobody needs `bundle exec`. It has to
# be the first require in the file: bundler resets the gem list when it sets up, and anything
# activated ahead of it warns about being unresolved on the way past.
require "bundler/setup"

require "vblank/original/data_guard_tasks"
require "vblank/original/shell_check_tasks"
require "vblank/testing/golden_task"
require "vblank/testing/ractor_settings"
require "vblank/testing/test_task"

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
# keeps none. `--no-ractor` in TESTOPTS runs it the ordinary way, for chasing one failure. The
# framework's settings put --ractor where rake cannot drop it, and take half the machine's cores
# unless MT_RACTOR_WORKERS says otherwise.
VBlank::Testing::RactorSettings.apply(ENV)

# The game, its tests, its tools and its films. The repository's own lib/ and test/ are what knows
# nothing about Wolfenstein.
GAME = "games/wolf3d"
LIBS = ["lib", "test", "#{GAME}/lib", "#{GAME}/test"].freeze

# `rake test` IS THE SUITE, as one run on the interpreter the cartridge is checked against.
# The framework's full set of tasks would play it again built as C, JavaScript and Ruby, which
# this game is not tested as; its single test task is the run without the rest.
E2E = "#{GAME}/test/e2e"
EVERYDAY_TESTS = FileList["test/**/test_*.rb", "#{GAME}/test/**/test_*.rb"].exclude("#{E2E}/**/*")
VBlank::Testing::TestTask.new(:test) do |t|
  t.libs = LIBS.dup
  t.test_files = EVERYDAY_TESTS
  t.warning = false
  t.description = "Run the suite (one file with TEST=#{GAME}/test/test_maps.rb, one test with " \
                  'TESTOPTS="--name=/pattern/")'
end

# `rake e2e` IS WHAT UNPACKS A WHOLE COPY: a whole build played from its data pack, and the pack
# held to the readers on both real copies, every song of the music played through the chip. Each
# takes minutes the first time after the unpacking changes, so it is run sparingly, not with the
# suite: after a change to an unpacking or to what a whole build reads from its pack.
VBlank::Testing::TestTask.new(:e2e) do |t|
  t.libs = LIBS.dup
  t.test_files = FileList["#{E2E}/**/test_*.rb"]
  t.warning = false
  t.description = "Run the tests that unpack a whole copy (minutes; after a change to an unpacking)"
end

# THE CHECK BEFORE A COMMIT: the files the game's test/golden.txt names, each from the game's own
# folder, and a few of the suite's others drawn at random, never e2e's. Past the framework's limit
# it fails however well the tests did, so every game built on it has the same one and this run
# cannot grow into one nobody bothers with.
VBlank::Testing::GoldenTask.new(list: "#{GAME}/test/golden.txt", from: GAME,
                                test_files: FileList["#{GAME}/test/**/test_*.rb"].exclude("#{E2E}/**/*").to_a) do |t|
  t.libs = LIBS.dup
  t.warning = false
end

# NONE OF WOLFENSTEIN'S DATA GOES IN A COMMIT. .gitignore keeps it out of `git add`; this is the
# backstop for what gets staged anyway, run by .githooks/pre-commit (`rake data_guard:install` once
# per clone). Besides the cartridges and saves the framework refuses for the Advance, it refuses:
# the original's files, which end in the release they belong to (VSWAP.WL6), and its DOS program;
# a palette written out of the copy; the folders a copy is dropped into or converted into, and the
# ones the build, the music and the films write to.
VBlank::Original::DataGuardTasks.new do |t|
  t.consoles = %i[gba]
  t.suffixes = %w[wl6 wl1 sod sdm exe pal]
  t.folders = %w[data/ assets/ tmp/ /.cache/]
end

# `rake shell:check`: the game built as a shell with no copy in reach, its LOAD ROM handed the copy
# wolf3d.yml names (WOLF3D_DATA=~/path/to/wolf3dsw checks the shareware instead), the pack it keeps
# held byte for byte to the all-in-one build's, and a tape played on both starts and on the all-in-one
# build, picture for picture and sound for sound (VBlank::Live::ShellCheck).
#
# THE TAPE is the bot finishing the shareware's first floor from power-on, recorded with
# games/wolf3d/tools/play_shareware.rb --floors 1 --music on its fixed random numbers (seed 1). It is
# presses alone, and the check's builds start the random numbers where the game does, so there the
# same presses play another fight: through the menus onto the floor, the pistol emptied into the
# guards, a kill, wounds, the knife out, but not the floor's end. That is as good, since the check
# holds the shell to the all-in-one build on the same presses, not to the bot's run.
VBlank::Original::ShellCheckTasks.new do |t|
  t.game_file = "#{GAME}/wolf3d.rb"
  t.tape = "#{GAME}/shell-check--shareware-floor-1.tape"
end

# The check compares whole builds as a player gets them. A WOLF3D_* dial left in the environment
# reaches neither build today (wolf3d.rb reads the environment only when it is the file run), and
# this keeps it so: the check stops before it starts if any dial is set.
namespace :shell do
  task :refuse_dials do
    require_relative "#{GAME}/lib/wolf3d"
    set = Wolf3D.settings_from(ENV).keys.map { |name| Wolf3D::DIALS.fetch(name) }
    unless set.empty?
      abort "shell:check: #{set.join(', ')} is set. The check compares whole builds with no dials. " \
            "Unset #{set.join(' and ')}, then run the check again."
    end
  end
end
task "shell:check" => "shell:refuse_dials"

# A FILM: an MP4 of the frames that show one thing, for the operator to watch without running
# anything. Each is a file in the game's films/ that hands VBlank::Diagnostics::Film what to play;
# this runs it and writes .cache/films/<name>.mp4, which git never sees. It needs ImageMagick and
# ffmpeg, and says which one is missing.
desc "Make the film #{GAME}/films/NAME.rb as .cache/films/NAME.mp4"
task :film do
  films = Dir["#{GAME}/films/*.rb"].map { |f| File.basename(f, ".rb") }
  name = ENV.fetch("NAME") { abort "Give the film's name: rake film NAME=turning. The films are: #{films.join(', ')}." }
  abort "There is no film called #{name}. The films are: #{films.join(', ')}." unless films.include?(name)

  mkdir_p ".cache/films"
  ruby "#{GAME}/films/#{name}.rb", ".cache/films/#{name}.mp4"
  puts "Wrote .cache/films/#{name}.mp4"
end

desc "Build #{GAME}/wolf3d.gba"
task :build do
  ruby "#{GAME}/wolf3d.rb"
end

# The WOLF3D_* dials that are set, as --set arguments for the framework's own `vblank` command.
# wolf3d.rb reads the environment only when it is the file run, and under `vblank` it is not, so
# the dials have to be handed over. Loading the library to learn their names costs a second, and
# keeps one list of them.
def dial_arguments
  require_relative "#{GAME}/lib/wolf3d"
  settings = Wolf3D.settings_from(ENV).map { |name, value| "#{name}=#{value}" }
  settings.empty? ? [] : ["--set", *settings]
end

namespace :build do
  # The same game as a program for this computer: a window, with the keyboard as the console's
  # buttons (mGBA's keys). The framework builds it — `vblank build --format=native`.
  desc "Build wolf3d-desktop, the game as a desktop app (the WOLF3D_* dials work as for build)"
  task :desktop do
    sh "bundle", "exec", "vblank", "build", "#{GAME}/wolf3d.rb", "--format=native", "--output=wolf3d-desktop",
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
        sh "bundle", "exec", "vblank", "build", "#{GAME}/wolf3d.rb", "--format=native", "--target=#{target}",
           "--output=#{output}", *dial_arguments
      end
    end
  end

  # The CARTRIDGE's frames, through `vblank profile`: what the build made of each routine and
  # which ones fit in the console's quick memory, then the game run in the emulator and where its
  # frames went. OPTS goes to that command as it is, so its own options need no list here —
  # `vblank help profile` has them. Left alone it measures the game as it boots, which is the
  # menu, so name the scene; and a player standing still costs little, so hold something:
  #
  #   rake build:gba_profile WOLF3D_FLOORS=1 OPTS="--scene playing --keys up"
  desc 'Where the CARTRIDGE\'s frames go, run in the emulator (OPTS="--scene playing --keys up" ' \
       "passes vblank profile options)"
  task :gba_profile do
    sh "bundle", "exec", "vblank", "profile", "#{GAME}/wolf3d.rb", *dial_arguments, *ENV.fetch("OPTS", "").split
  end

  # NOT the game's frames. This samples the BUILD — Ruby, on this machine, turning your copy of
  # Wolfenstein into a cartridge. Where the finished cartridge spends its 228 scanlines a frame
  # is a different question, and build:gba_profile answers that one.
  desc "Where the BUILD's time goes: sample a full build, for speedscope.app"
  task :profile do
    ruby "#{GAME}/tools/profile_build.rb"
  end
end

task default: :test
