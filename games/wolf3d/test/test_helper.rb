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
