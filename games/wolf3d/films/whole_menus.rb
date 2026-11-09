# frozen_string_literal: true

# A WHOLE BUILD'S TITLE, THEN ITS MAIN MENU, every picture drawn from the data pack (MenuPictures):
# the title shortened by the unpacking, the plate over the rows, the gun. The copy is the one this
# machine names, so the film is made once for each:
#
#   rake film NAME=whole_menus
#   WOLF3D_COPY=shareware rake film NAME=whole_menus
require_relative "../lib/wolf3d"
require_relative "../test/support/menu_scene"
require "stringio"

scene = Wolf3DTest::MenuScene
program = Wolf3D::GAME.checked_program(err: StringIO.new, settings: { screen: "title", hold: "whole" })
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { Wolf3D.data.label => -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") } },
                               parts: [1..scene::FILM_FRAMES],
                               keys: ->(frame) { scene.keys(frame) })
