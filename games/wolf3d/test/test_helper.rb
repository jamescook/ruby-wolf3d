# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/wolf3d"
# AFTER THE GAME, so the game's own block is checked as any game's is. Past this line the blocks a
# test writes are not, because a test names its own helpers and a game has no reason to.
require "vblank/testing"
require "vblank/testing/in_ractors"
require_relative "support/field"
require_relative "support/turning_scene"
require_relative "support/episode_scene"
require_relative "support/menu_scene"
require_relative "support/lift_scene"
require_relative "support/article_scene"
require_relative "support/shot_guard_scene"
require_relative "support/unpacked_pack"
VBlank.require_game_file "support/counting_worlds"

module Wolf3DTest
  include Field
  include VBlank::Testing

  # THE FRAMEWORK'S NAMES, SAID ONCE. Each of these lives a module or two down in VBlank, and
  # a test that spelled the whole path every time would wrap at every call. Naming them here
  # also means the next time the framework moves one, one line moves with it.
  Reference = VBlank::IR::Backends::Reference # the oracle: runs a program in-process
  SaveImage = VBlank::IR::SaveImage # a cartridge's save memory, for Reference.new(save:)
  GBA = VBlank::IR::Backends::GBA
  Builder = VBlank::Builder
  ROM = VBlank::Cartridge::ROM
  Verifier = VBlank::Diagnostics::Verifier # the real cartridge, in the emulator
  Constants = VBlank::Console::Hardware # KEY_UP and the rest of the hardware's names
  Fraction = VBlank::DSL::Fraction # a number with a fractional part, kept in the low bits

  # THE SUITE RUNS IN RACTORS — Ruby's way of using several cores in one process — so including
  # this hands the class to the pool and freezes every constant it declares after that line, all
  # the way down, because a worker may read a constant only when nothing in it can change. The
  # framework's InRactors is the whole of that rule.
  def self.included(test_class)
    super
    test_class.include(VBlank::Testing::InRactors)
  end

  # THE REAL COPY OF THE GAME, for the tests that check us against the world rather than against
  # ourselves. The suite requires it: nothing set stops the test with what to set
  # (VBlank::Original::NotSet), and a copy the build refuses stops it with why. It is the copy the
  # game reads, checked once per worker, because checking it reads every file.
  def real_copy = Wolf3D.data || original_copy(Wolf3D::GameData.original)

  # THE REAL COPY OF THE SHAREWARE, named by the `shareware` line of wolf3d.yml, beside whatever
  # copy the rest of the suite reads. Required as the other is.
  def real_shareware
    Ractor.current[:wolf3d_real_shareware] ||= begin
      shareware = original_copy(Wolf3D::GameData.original(env: { Wolf3D::GameData::COPY_VAR => "shareware" }))
      Wolf3D::GameData.new(dir: shareware.path, set: shareware.release)
    end
  end

  # +data+ (a GameData) as the framework names a copy, which a data pack is filled from: the one
  # folder, whichever release it holds.
  def original_of(data)
    VBlank::Original::Game.new(title: "Wolfenstein 3D", setting: "WOLF3D_DATA", settings_file: "/dev/null",
                               env: { "WOLF3D_DATA" => data.dir }, key: "data",
                               releases: Wolf3D::Vanilla::RELEASES, platform: :pc)
  end

  # EACH SLOT OF A DATA PACK AS +unpacking+ (an Original::Unpacking) LEAVES IT, handed its copy and
  # played the fastest way this machine has: built as C where zig is installed, else as Ruby, the way
  # a build plays it. Both are many times faster than the interpreter, which VBlank's own suite holds
  # them to, and the music through the chip is minutes as Ruby and seconds as C. The routine waits a
  # frame every 256 bytes it counts, and it counts fewer than the pack holds (a slot it leaves at
  # nought is never written), so the bytes give it frames to spare; a routine that has not finished
  # in them is a fault, not a short pack.
  #
  # KEPT IN THE BUILD'S OWN PACK CACHE (DataPack::CACHE). Its key is the copy's bytes, the routine
  # and its slots, VBlank and the Ruby, so a hit is exactly what this run would have written: a
  # change to any of them, or a copy a test damaged, runs the routine again. It is KEPT A PART AT A
  # TIME (DataPack::PARTS), so a change to one part replays that part and the parts that read its
  # slots: the block is handed the routine of just those, which is what it plays.
  #
  # +pack+ is the handle DataPack.declare gives.
  def slots_unpacked_by(pack)
    cache = VBlank::Original::PackCache.new(Wolf3D::DataPack::CACHE)
    cache.slot_bytes(pack.unpacking, parts: pack.unpacking_parts) do |playing, _names|
      frames = (playing.byte_size / 256) + 400
      run = playing.run_fastest(frames: frames)
      raise "the unpacking did not finish in #{frames} frames" unless playing.finished_in?(run)

      playing.slot_bytes_in(run)
    end
  end

  # WHOLE CARTRIDGES, BUILT ONCE AND KEPT, in a folder git ignores because a cartridge holds your
  # copy of the game. The key is the program the game's block builds, with its settings, so a
  # change to the game, to the copy it reads or to the framework builds it again, and nothing else
  # does. What the cache did is said at the end of the run.
  BUILDS = VBlank::Testing::CartridgeCache.new(File.expand_path("../../../.cache/builds", __dir__))
  Minitest.after_run { BUILDS.report }

  # THE SMALLEST CARTRIDGE THAT IS STILL THIS GAME, for the two tests that build the whole
  # thing rather than a floor of their own.
  #
  # The build ships every episode your copy holds, which is right for playing and wrong here:
  # on the registered release that is sixty floors, an 8MB cartridge and about a minute, and
  # what these tests want to know is only that the wiring works. One floor is a few seconds and
  # proves the same thing. The setting is handed to this build alone, so nothing another test is
  # building at the same moment sees it.
  def a_small_cartridge
    BUILDS.cartridge(Wolf3D::GAME, console: :gba, settings: { floors: 1 })
  end
end
