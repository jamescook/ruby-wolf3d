# frozen_string_literal: true

require_relative "test_helper"

# A track is a log of writes to the AdLib chip, so these play made-up logs and listen to what comes
# out. The numbers of the registers and the 700 ticks a second are id_sd.cpp's SDL_IMFMusicPlayer.
class TestOpl2Track < Minitest::Test
  include Wolf3DTest

  # Channel nought's modulator is operator cell 0x00 and its carrier 0x03. Each write is a register,
  # a value, and the ticks to wait after it.
  def a_held_note
    fnum = 0x241
    block = 4
    silent_modulator = [[0x40, 0x3f, 0], [0x60, 0xf0, 0], [0x80, 0x0f, 0]]
    loud_carrier = [[0x43, 0x00, 0], [0x63, 0xf0, 0], [0x83, 0x0f, 0], [0x23, 0x21, 0], [0x20, 0x21, 0]]
    tune = [[0xa0, fnum & 0xff, 0], [0xb0, 0x20 | (block << 2) | (fnum >> 8), 700]]
    silent_modulator + loud_carrier + tune
  end

  def rises_across_nought(samples)
    samples.each_cons(2).count { |before, after| before.negative? && !after.negative? }
  end

  CONSOLE = Wolf3D::Opl2Track::CONSOLE_SAMPLE_RATE
  COMPUTER = Wolf3D::Opl2Track::COMPUTER_SAMPLE_RATE

  def render(writes, rate: CONSOLE) = Wolf3D::Opl2Track.render(writes, rate: rate)

  def test_a_track_lasts_as_long_as_its_delays_say_at_seven_hundred_ticks_a_second
    assert_in_delta CONSOLE, render(a_held_note).length, 2
    assert_in_delta COMPUTER, render(a_held_note, rate: COMPUTER).length, 2
  end

  def test_a_note_sounds_at_the_pitch_its_registers_name
    # fnum * 49716 * 2^(block - 20): the chip's data sheet, and this one comes to about 440 Hz.
    hertz = 0x241 * 49_716 * (2.0**(4 - 20))

    assert_in_delta hertz, rises_across_nought(render(a_held_note)), 3
    assert_in_delta hertz, rises_across_nought(render(a_held_note, rate: COMPUTER)), 3
  end

  # A byte has little room, so the loudest moment of a track is put at the top of it.
  def test_a_track_is_as_loud_as_a_byte_holds
    assert_operator render(a_held_note).map(&:abs).max, :>=, 120
  end

  # Noise is added below the last step of a byte, which turns the static of rounding into a hiss. It
  # comes from a fixed seed, so the same track is the same bytes on every build.
  def test_the_same_track_renders_the_same_bytes
    assert_equal render(a_held_note), render(a_held_note)
  end

  def test_a_key_let_go_falls_silent
    released = a_held_note + [[0xb0, 0x00, 700]]
    samples = render(released)
    last_tenth = samples.last(samples.length / 10)

    assert_operator samples.first(samples.length / 2).map(&:abs).max, :>, 20
    assert_operator last_tenth.map(&:abs).max, :<, 3
  end

  # The second channel plays the octave above: one block higher. Together the two cross nought as
  # often as the higher note does alone, where the lower one by itself crosses half as often.
  def test_two_channels_sound_together
    second = a_held_note.map { |register, value, wait| [channel_one(register), register == 0xb0 ? value + 4 : value, wait] }
    # The first note's wait is taken out so both start together.
    both = render(a_held_note.map { |r, v, _| [r, v, 0] } + second)

    assert_operator rises_across_nought(both), :>, rises_across_nought(render(a_held_note)) * 3 / 2
  end

  # Channel one's cells sit one past channel nought's, and so do its pitch registers.
  def channel_one(register) = register + 1

  def test_an_additive_channel_lets_the_modulator_be_heard
    audible_modulator = [[0xc0, 0x01, 0], [0x40, 0x00, 0], [0x20, 0x21, 0], [0x60, 0xf0, 0], [0x80, 0x0f, 0]]
    quiet_carrier = [[0x43, 0x3f, 0], [0x63, 0xf0, 0], [0x83, 0x0f, 0]]
    key = [[0xa0, 0x41, 0], [0xb0, 0x32, 700]]
    samples = render(audible_modulator + quiet_carrier + key)

    assert_operator samples.map(&:abs).max, :>, 20
  end

  # Floor 1's theme is 56,000 ticks in the game's own file. That is the eighty seconds it runs for at
  # the original's 700 ticks a second, and it would run a hundred at the 560 of other games' files.
  def test_a_real_track_lasts_as_long_as_seven_hundred_ticks_a_second_makes_it
    music = Wolf3D::AdlibMusic.from(real_copy)
    samples = render(music.writes(Wolf3D::Music::GETTHEM).first(200))
    ticks = music.writes(Wolf3D::Music::GETTHEM).first(200).sum(&:last)

    assert_in_delta ticks * CONSOLE / 700.0, samples.length, 2
  end
end
