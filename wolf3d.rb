#!/usr/bin/env ruby
# frozen_string_literal: true

# Build wolf3d.gba:
#
#   ruby games/wolf3d/wolf3d.rb
#
# Requiring this file (a test does) builds nothing and writes nothing.

require_relative "lib/wolf3d"

Wolf3D.report if $PROGRAM_NAME == __FILE__
# The WOLF3D_* dials are read here, where a cartridge is built from the command line, and handed
# to this one build — see Wolf3D::DIALS.
Wolf3D::GAME.write_if_main(settings: Wolf3D.settings_from(ENV))
