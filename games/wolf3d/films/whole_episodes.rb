# frozen_string_literal: true

# A WHOLE BUILD'S EPISODE LIST, down once and A, then A on the difficulty screen and the first
# floor that starts: the shareware's build steps over the five episodes it lacks and starts the
# first, the six episodes' starts the second. The copy is the one this machine names, so the film
# is made once for each:
#
#   rake film NAME=whole_episodes
#   WOLF3D_COPY=shareware rake film NAME=whole_episodes
require_relative "../lib/wolf3d"
require_relative "../test/support/episode_scene"
require "stringio"

scene = Wolf3DTest::EpisodeScene
program = Wolf3D::GAME.checked_program(err: StringIO.new, settings: scene::SETTINGS)
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { Wolf3D.data.label => -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") } },
                               parts: [1..scene::PLAYING_FRAMES],
                               keys: ->(frame) { scene.keys(frame) })
