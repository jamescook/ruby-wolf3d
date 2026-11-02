# frozen_string_literal: true

require_relative "test_helper"

# AUDIOT, READ. The layout is the original's AdLibSound (id_sd.h): six bytes of length and priority,
# sixteen of instrument, one of block, then a byte for each 1/140 of a second. These bytes are made
# up for the test, and test_shareware.rb holds them against a real copy.
class TestAdlibSounds < Minitest::Test
  include Wolf3DTest

  AdLib = Wolf3D::AdlibSounds

  INSTRUMENT = [0x21, 0x01, 0x2a, 0x80, 0xf2, 0xf5, 0x1f, 0x88, 0x01, 0x03, 0x0d, 0, 0, 0, 0, 0].freeze

  def chunk(notes, priority: 42, block: 5)
    ([notes.length].pack("V") + [priority].pack("v") + INSTRUMENT.pack("C*") + [block].pack("C") + notes.pack("C*"))
  end

  def sounds(chunks)
    at = 0
    offsets = chunks.map { |bytes| at.tap { at += bytes.bytesize } } << at
    AdLib.new(head: offsets.pack("V*"), audio: chunks.join)
  end

  def with_effect(number, bytes) = sounds(Array.new(AdLib::FIRST_CHUNK + number, "") + [bytes])

  def test_an_effect_is_found_past_the_pc_speaker_sounds
    effect = with_effect(3, chunk([9, 0, 8])).effect(3)

    assert_equal [9, 0, 8], effect.notes
    assert_equal 42, effect.priority
    assert_equal 5, effect.block
  end

  def test_the_instrument_is_split_into_its_two_operators
    instrument = with_effect(0, chunk([1])).effect(0).instrument

    assert_equal [0x21, 0x2a, 0xf2, 0x1f, 0x01], instrument.modulator.to_h.values
    assert_equal [0x01, 0x80, 0xf5, 0x88, 0x03], instrument.carrier.to_h.values
  end

  def test_a_chunk_with_nothing_in_it_is_no_effect
    assert_nil with_effect(1, "").effect(1)
  end

  def test_a_number_past_the_end_is_no_effect
    assert_nil with_effect(1, chunk([1])).effect(50)
  end
end
