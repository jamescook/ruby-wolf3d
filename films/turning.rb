# frozen_string_literal: true

# BJ TURNING ON THE SPOT on the first floor, walking and then running: 1.75 degrees a pass, then
# 3.5, the original's rates. One side, ours: the original is source, not a cartridge.
#
#   rake film NAME=turning
require_relative "../lib/wolf3d"
require_relative "../test/support/turning_scene"
require "stringio"

scene = Wolf3DTest::TurningScene
rom = Wolf3D.build_rom(settings: scene::CARTRIDGE_SETTINGS, out: StringIO.new, err: StringIO.new)
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { "ours" => -> { VBlank::Diagnostics::Verifier.new(rom, frames: 0) } },
                               parts: [1..scene.run_ends],
                               keys: ->(frame) { scene.keys(frame) })
