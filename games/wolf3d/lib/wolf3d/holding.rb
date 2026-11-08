# frozen_string_literal: true

module Wolf3D
  # WHAT A BUILD HOLDS: only what its floors use, or the whole game at the original's own limits.
  #
  # A CARTRIDGE IS TRIMMED. Room on it is short, so it holds the walls and sprites its floors build
  # with, room for the most doors and guards any of its floors has, and code for the enemy kinds
  # that are there. Its shape follows the copy it was built from, and the dials that pick floors.
  #
  # A COMPUTER BUILD IS WHOLE. A shell build (VBlank's LOAD ROM) is made before anybody's copy is
  # read, so nothing in its shape may come from a copy: it holds every wall and sprite picture,
  # room for as much as the original allows on a floor, and every enemy kind, whichever release
  # is loaded into it later.
  #
  # SIZED FOR SPEAR OF DESTINY TOO, though Vanilla accepts only the shareware and the six episodes
  # today. Spear is the next release this game is to read, and a shell sized for it then loads it
  # with no change of shape; until then the extra room holds nothing.
  class Holding
    # The most of each thing one floor may hold. wolf4sdl wl_def.h: MAXDOORS, MAXACTORS (the
    # player is one of them, so one fewer is left for guards) and MAXSTATS. The original sets no
    # limit on walls that move or on lifts; these are the most any floor of the three releases has
    # (a floor of the six episodes has 179 walls that move, Spear's busiest has 17 lifts), with
    # room to spare.
    ROOM = Ractor.make_shareable({ doors: 64, guards: 149, pieces: 400, pushwalls: 192, lifts: 24 })

    # Every page of walls and doors in the largest VSWAP, and every sprite in the largest, counted
    # off the copies (VSWAP's header says them; the original's source does not): Spear's has 134
    # pages, the six episodes' and the shareware's 106; the six episodes' and the shareware's have
    # 436 sprites, Spear's 421.
    WALL_PAGES = 134
    SPRITES = 436

    # The most floors a release has: the six episodes' sixty. MAPHEAD keeps room for a hundred.
    FLOORS = 60

    def self.trimmed = new(whole: false)
    def self.whole = new(whole: true)

    # WHICH ONE A BUILD HOLDS. +asked+ is the build's `hold` setting, "whole" or "trimmed", or nil to
    # let the build decide: whole on a computer, unless a dial picked some floors to measure, since a
    # build made to measure one floor wants that floor's shape.
    def self.for(asked, computer:, dialled:)
      case asked
      when nil then computer && !dialled ? whole : trimmed
      when "whole" then whole
      when "trimmed" then trimmed
      else raise ArgumentError, "The hold setting (WOLF3D_HOLD) cannot read #{asked.inspect}. Give whole or trimmed."
      end
    end

    def initialize(whole:)
      @whole = whole
    end

    def whole? = @whole

    # The room a whole build keeps for one floor's +kind+, or nil for a trimmed one.
    def room_for(kind) = whole? ? ROOM.fetch(kind) : nil
  end
end
