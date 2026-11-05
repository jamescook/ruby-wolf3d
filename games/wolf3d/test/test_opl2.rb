# frozen_string_literal: true

require_relative "test_helper"

# THE CHIP, HELD TO ITS DATA SHEET: what a pitch is, what the envelope does and what the modulator
# does to the carrier. Each number here comes from the YM3812's documented behaviour.
class TestOpl2 < Minitest::Test
  include Wolf3DTest

  Opl2 = Wolf3D::Opl2
  AdLib = Wolf3D::AdlibSounds

  # Multiple 1, the sustaining envelope, attack at once, no decay. Level 63 is as quiet as an
  # operator goes, which leaves the carrier alone.
  HOLDING = { char: 0x21, scale: 0, attack: 0xf0, sustain: 0x00, wave: 0 }.freeze
  SILENT_MODULATOR = HOLDING.merge(scale: 0x3f).freeze

  def instrument(modulator: SILENT_MODULATOR, carrier: HOLDING)
    AdLib::Instrument.new(modulator: AdLib::Operator.new(**modulator), carrier: AdLib::Operator.new(**carrier))
  end

  def effect(notes, block: 4, **) = AdLib::Effect.new(priority: 1, instrument: instrument(**), block: block, notes: notes)

  def rising_crossings(samples) = samples.each_cons(2).count { |a, b| a.negative? && !b.negative? }

  def loudness(samples) = samples.map(&:abs).max

  # F = fnum * 49716 * 2^(block - 20)
  def test_pitch_comes_from_the_note_and_the_block
    samples = Opl2.render(effect([200] * 70, block: 5))
    heard = rising_crossings(samples.first(Opl2::RENDER_RATE / 2)) * 2

    assert_in_delta 200 * 49_716 * (2.0**-15), heard, 6
  end

  def test_a_block_higher_is_an_octave_higher
    low = rising_crossings(Opl2.render(effect([200] * 70, block: 4)).first(3000))
    high = rising_crossings(Opl2.render(effect([200] * 70, block: 5)).first(3000))

    assert_in_delta low * 2, high, 2
  end

  def test_the_multiple_scales_the_pitch
    doubled = HOLDING.merge(char: 0x22)
    plain = rising_crossings(Opl2.render(effect([200] * 70)).first(3000))
    twice = rising_crossings(Opl2.render(effect([200] * 70, carrier: doubled)).first(3000))

    assert_in_delta plain * 2, twice, 2
  end

  def test_a_nought_is_a_rest
    samples = Opl2.render(effect([200] * 14 + [0] * 28 + [200] * 14, carrier: HOLDING.merge(sustain: 0x0f)))
    middle = samples[(Opl2::RENDER_RATE * 0.2).to_i, 200]

    assert_operator loudness(samples), :>, 60
    assert_operator loudness(middle), :<, 8, "the fastest release has finished by then"
  end

  def test_the_level_is_three_quarters_of_a_decibel_a_step
    full = loudness(Opl2.render(effect([200] * 28)))
    lower = loudness(Opl2.render(effect([200] * 28, carrier: HOLDING.merge(scale: 8))))

    assert_in_delta full * (10**(-6.0 / 20)), lower, 3
  end

  def test_a_decay_falls_to_the_sustain_level
    decays = HOLDING.merge(attack: 0xfc, sustain: 0x40)
    samples = Opl2.render(effect([200] * 70, carrier: decays))

    assert_in_delta 127 * (10**(-12.0 / 20)), loudness(samples.last(1500).first(300)), 3
  end

  def test_the_lowest_sustain_is_nearly_silence
    decays = HOLDING.merge(attack: 0xfc, sustain: 0xf0)
    samples = Opl2.render(effect([200] * 70, carrier: decays))

    assert_operator samples.length, :<, 2000, "the rest of the half second is silence, and is cut off"
  end

  def test_a_slow_attack_climbs
    samples = Opl2.render(effect([200] * 140, carrier: HOLDING.merge(attack: 0x30)))

    assert_operator loudness(samples.first(300)), :<, loudness(samples.last(3000)) / 2
    assert_operator loudness(samples.first(300)), :>, 0, "and is heard from the start"
  end

  def test_a_rest_before_the_first_note_is_silence_and_then_the_note
    samples = Opl2.render(effect([0] * 7 + [200] * 14))

    assert_operator samples.length, :>, 1000
    assert_equal 0, loudness(samples.first(300))
  end

  def test_a_modulator_changes_the_shape_but_not_the_pitch_of_the_note
    plain = Opl2.render(effect([200] * 70))
    bent = Opl2.render(effect([200] * 70, modulator: HOLDING.merge(scale: 0x10)))

    refute_equal plain, bent
    assert_operator rising_crossings(bent.first(3000)), :>=, rising_crossings(plain.first(3000))
  end

  def test_half_sine_is_silent_for_half_of_each_cycle
    half = Opl2.render(effect([200] * 70, carrier: HOLDING.merge(wave: 1)))

    assert_operator half.count(&:negative?), :<, half.length / 20
  end

  def test_a_render_is_signed_bytes_and_stops_when_the_sound_does
    samples = Opl2.render(effect([200] * 14))

    assert(samples.all? { |sample| sample.between?(-128, 127) })
    assert_operator samples.length, :<, Opl2::RENDER_RATE, "no silent tail"
  end

  def test_the_same_effect_renders_the_same
    assert_equal Opl2.render(effect([200] * 14)), Opl2.render(effect([200] * 14))
  end
end
