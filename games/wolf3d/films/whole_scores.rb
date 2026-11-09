# frozen_string_literal: true

# A WHOLE BUILD'S TABLE OF HIGH SCORES, its names in the small alphabet drawn from the data pack
# (SmallLetters), booted on and faded in. The copy is the one this machine names, so the film is made
# once for each:
#
#   rake film NAME=whole_scores
#   WOLF3D_COPY=shareware rake film NAME=whole_scores
require_relative "../lib/wolf3d"
require_relative "../test/support/menu_scene"
require "stringio"

scene = Wolf3DTest::MenuScene
program = Wolf3D::GAME.checked_program(err: StringIO.new, settings: { screen: "scores", hold: "whole" })
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { Wolf3D.data.label => -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") } },
                               parts: [1..scene::FRAMES],
                               keys: ->(_frame) { [] })
