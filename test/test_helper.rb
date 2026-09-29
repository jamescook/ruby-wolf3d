# frozen_string_literal: true

require "minitest/autorun"
require "minitest/ractor"
require_relative "../lib/wolf3d"

module Wolf3DTest
  # THE FRAMEWORK'S NAMES, SAID ONCE. Each of these lives a module or two down in ruby-gba, and
  # a test that spelled the whole path every time would wrap at every call. Naming them here
  # also means the next time the framework moves one, one line moves with it.
  Reference = RubyGBA::IR::Backends::Reference # the oracle: runs a program in-process
  GBA = RubyGBA::IR::Backends::GBA
  Builder = RubyGBA::Builder
  ROM = RubyGBA::Cartridge::ROM
  Verifier = RubyGBA::Diagnostics::Verifier # the real cartridge, in the emulator
  Constants = RubyGBA::Console::Hardware # KEY_UP and the rest of the hardware's names
  Fraction = RubyGBA::DSL::Fraction # a number with a fractional part, kept in the low bits

  # EVERY FIXTURE A TEST CLASS PARKS IN A CONSTANT IS FROZEN ALL THE WAY DOWN, the moment it is
  # declared. The suite runs in Ractors — Ruby's way of using several cores in one process — and
  # a worker may read a constant only when nothing in it can change. A `.freeze` on the outside
  # is not enough: a frozen list of unfrozen lists is still refused.
  #
  # Ruby tells a class when a constant is added to it, so this is the whole rule, in one place,
  # with nothing for a test file to remember. It reaches the constants declared after the file's
  # `include Wolf3DTest`, which is the first line of every test class.
  #
  # A nested class or module is code, not a fixture, and is left alone. Anything that refuses to
  # freeze — a block reaching for a variable around it — stops the file loading, naming the
  # constant: left as it was, it would only be refused later, inside whichever test reached it.
  module FreezesItsConstants
    def const_added(name)
      super
      value = const_get(name, false)
      return if value.is_a?(Module) || Ractor.shareable?(value)

      shareable = Ractor.make_shareable(value)
      return if shareable.equal?(value)

      remove_const(name)
      const_set(name, shareable)
    rescue Ractor::IsolationError => e
      raise Ractor::IsolationError, "#{self}::#{name} cannot be frozen for the Ractors: #{e.message}"
    end
  end

  def self.included(test_class)
    super
    test_class.extend(FreezesItsConstants)
    test_class.parallelize_me!
  end

  # A real copy of the game, for the few tests that check us against the world rather than
  # against ourselves. The suite never depends on one being here.
  def game_data_or_skip
    Wolf3D::GameData.find ||
      skip("no copy of Wolfenstein 3D found — set #{Wolf3D::GameData::ENV_VAR} to check against one")
  end

  # THE SMALLEST CARTRIDGE THAT IS STILL THIS GAME, for the two tests that build the whole
  # thing rather than a floor of their own.
  #
  # The build ships every episode your copy holds, which is right for playing and wrong here:
  # on the registered release that is sixty floors, an 8MB cartridge and about a minute, and
  # what these tests want to know is only that the wiring works. One floor is a few seconds and
  # proves the same thing. The setting is handed to this build alone, so nothing another test is
  # building at the same moment sees it.
  def a_small_cartridge = Wolf3D.build_rom(out: StringIO.new, err: StringIO.new, settings: { floors: 1 })
end
