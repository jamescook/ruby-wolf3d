# frozen_string_literal: true

# A WHOLE BUILD'S SCREEN BETWEEN FLOORS, its big letters drawn from the data pack (BigLettering): the
# first floor's secret lift ridden, and the screen counting up its figures. The copy is the one this
# machine names, so the film is made once for each:
#
#   rake film NAME=whole_tally
#   WOLF3D_COPY=shareware rake film NAME=whole_tally
require_relative "../lib/wolf3d"
require_relative "../test/support/lift_scene"
require "stringio"

scene = Wolf3DTest::LiftScene
program = Wolf3D::GAME.checked_program(err: StringIO.new,
                                       settings: { floors: 1, screen: "playing", hold: "whole", start: scene.start })
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { Wolf3D.data.label => -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") } },
                               parts: [scene::PULL_FRAME..scene::FILM_FRAMES],
                               keys: ->(frame) { scene.keys(frame) })
