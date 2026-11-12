# frozen_string_literal: true

module Wolf3D
  # A WHOLE BUILD'S DATA PACK: everything of the copy the game draws and plays, worked out by the
  # game itself at a shell's LOAD ROM, or as an all-in-one build is made. The floors are
  # FloorUnpacking's slots, VSWAP's pictures PictureUnpacking's and its recorded sounds
  # SoundUnpacking's, AUDIOT's AdLib effects AdlibUnpacking's and its music MusicUnpacking's,
  # VGAGRAPH's VgagraphUnpacking's, and the status bar's BarUnpacking's, the small alphabet's
  # SmallLetterUnpacking's and the end articles' pages EndArticleUnpacking's, made out of VGAGRAPH's;
  # one routine fills them all, in that order.
  module DataPack
    # THE PACK'S VERSION, which names this build of the game in the pack's header. Must change
    # whenever the slots or what the routine writes into them change, so a player's pack is made
    # again.
    VERSION = "17"

    # Where packs are kept between builds, out of git, so only the first build from a copy runs the
    # routine: the repository's own .cache, wherever the build was started from. Worked out as this
    # file loads (it is games/wolf3d/lib/wolf3d/), since the game's own code may not reach the files.
    CACHE = File.expand_path("../../../../.cache/packs", __dir__).freeze

    # Each part of the pack: its slots (`declare`) and the part of the routine that fills them.
    PARTS = [FloorUnpacking, PictureUnpacking, SoundUnpacking, AdlibUnpacking, MusicUnpacking, VgagraphUnpacking,
             BarUnpacking, SmallLetterUnpacking, EndArticleUnpacking].freeze

    # THE PACK, declared on +game+ (a build's self) and filled from +from+ (an Original::Game naming
    # the copy). Hands back the pack's handle.
    def self.declare(game, from:)
      game.data_pack(from: from, version: VERSION, formats: [MapPlaneFormat], cache: CACHE) do |slots|
        PARTS.each { |part| part.declare(slots) }
        # The routine is a program of its own, and the block runs on its builder: self here.
        slots.fill_from_copy do |copy, pack, release|
          PARTS.each { |part| part.new(self, copy, pack, release).fill }
        end
      end
    end
  end
end
