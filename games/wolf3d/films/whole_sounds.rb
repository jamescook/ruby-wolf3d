# frozen_string_literal: true

# THE FIRST FLOOR'S FIRST GUARD SHOT over the floor's song, a trimmed build beside a whole one: the
# whole build's gun, guard, scream and music are its data pack's, which the unpacking made from the
# copy, the trimmed build's made from the copy while it was built. They sound the same. The copy is
# the one this machine names, so the film is made once for each:
#
#   rake film NAME=whole_sounds
#   WOLF3D_COPY=shareware rake film NAME=whole_sounds
require_relative "../lib/wolf3d"
require_relative "../test/support/shot_guard_scene"
require "stringio"

scene = Wolf3DTest::ShotGuardScene
settings = scene.settings(Wolf3D.maps[0])
sides = %w[trimmed whole].to_h do |hold|
  program = Wolf3D::GAME.checked_program(err: StringIO.new, settings: settings.merge(hold: hold))
  ["#{Wolf3D.data.label}, #{hold}", -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") }]
end
VBlank::Diagnostics::Film.make(ARGV.fetch(0), sides: sides, parts: [1..scene::FRAMES], keys: ->(frame) { scene.keys(frame) })
