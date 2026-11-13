# frozen_string_literal: true

module Wolf3D
  # WHERE THE GAME'S RECORDINGS COME FROM: the recorded sounds of VSWAP, the AdLib effects and the
  # music, which Sounds and Music make into instruments and play.
  #
  # A TRIMMED BUILD BAKES THEM (Baked), made from the copy while it is built, and holds only the ones
  # that copy has. A WHOLE BUILD TAKES THEM FROM ITS DATA PACK (Packed), where SoundUnpacking,
  # AdlibUnpacking and MusicUnpacking leave each in a room of its own: it holds every one the
  # original has, and which of them this copy has is read from the pack as the game plays, a sound
  # the copy lacks being nought long there and so silent. Sounds and Music ask for each here and
  # never which kind of build they are in.
  #
  # Each is asked by the original's number: a chunk of VSWAP's sounds, an effect or a track of AUDIOT.
  module Recordings
    # EVERY COUNT OF RECORDINGS TO ROLL AMONG divides this, so a roll of it shared out among however
    # many this copy has gives each the same chance (#roll_held). Up to seven, the death screams.
    ROLL_SPAN = 420

    # Must be checked for any list rolled among: a count that does not divide ROLL_SPAN favours some.
    def self.check_roll(chunks)
      return if (1..chunks.length).all? { |count| (ROLL_SPAN % count).zero? }

      raise ArgumentError, "Rolling among #{chunks.length} recordings needs a ROLL_SPAN they all divide."
    end

    # THE RECORDINGS AS THE COPY HOLDS THEM, made while building. +vswap+ (Vswap), +adlib+
    # (AdlibSounds) and +music+ (AdlibMusic) are the copy's, each nil for a build without them.
    class Baked
      def initialize(build, vswap: nil, adlib: nil, music: nil)
        @b = build
        @vswap = vswap
        @adlib = adlib
        @music = music
        # A computer has room for the music at the most a speaker takes; the console at less.
        @music_rate = build.built_for_computer? ? Opl2Track::COMPUTER_SAMPLE_RATE : Opl2Track::CONSOLE_SAMPLE_RATE
      end

      # THE CHUNKS OF +chunks+ THIS BUILD HOLDS: the ones the copy has.
      def sounds_held(chunks) = @vswap ? chunks.select { |chunk| recording(chunk) } : []

      # Chunk +chunk+ as a sample called +name+.
      def declare_sound_sample(name, chunk)
        sound = recording(chunk)
        @b.sample(name, pcm: sound.pcm, rate: sound.rate)
      end

      # ...or as an instrument, handing back how many frames it lasts.
      def declare_sound_instrument(name, chunk)
        sound = recording(chunk)
        @b.instrument(name, pcm: sound.pcm, rate: sound.rate)
        ((sound.pcm.length.to_f / sound.rate) * AdlibSounds::FRAMES_PER_SECOND).ceil
      end

      # How many frames chunk +chunk+ lasts, nought for one this build does not hold.
      def sound_frames(chunk)
        sound = @vswap && recording(chunk) or return 0

        ((sound.pcm.length.to_f / sound.rate) * AdlibSounds::FRAMES_PER_SECOND).round
      end

      # A place in +chunks+, rolled, every one of which this build holds: the roll Packed makes, so a
      # trimmed build and a whole one made from the same copy pick the same.
      def roll_held(chunks)
        Recordings.check_roll(chunks)
        @b.rand(0...ROLL_SPAN) * chunks.length / ROLL_SPAN
      end

      # THE EFFECTS OF +numbers+ (a name for each number) THIS BUILD HOLDS: the ones the copy has.
      def adlib_held(numbers) = @adlib ? numbers.select { |_, number| @adlib.recording(number) } : {}

      # Effect +number+ as an instrument called +name+, handing back how many frames it lasts.
      def declare_adlib_instrument(name, number)
        recording = @adlib.recording(number)
        @b.instrument(name, pcm: recording.pcm, rate: recording.rate)
        recording.sample_frames
      end

      # THE FRAMES EACH OF +numbers+ PLAYS NOTES FOR, and its priority, each a table of the effects
      # held in that order and a row of nought after them for the place that names none.
      def adlib_note_frames(name, numbers) = @b.table(name, numbers.map { |n| @adlib.recording(n).note_frames } + [0], width: :half)
      def adlib_priorities(name, numbers) = @b.table(name, numbers.map { |n| @adlib.recording(n).priority } + [0], width: :byte)

      # THE TRACKS OF +tracks+ THIS BUILD HOLDS: the ones the copy has.
      def songs_held(tracks) = @music ? tracks.reject { |track| @music.writes(track).empty? } : []

      # Track +track+ as an instrument called +name+, handing back how many frames it lasts.
      def declare_song_instrument(name, track)
        pcm = @music.recording(track, rate: @music_rate)
        @b.instrument(name, pcm: pcm, rate: @music_rate)
        ((pcm.length.to_f / @music_rate) * AdlibSounds::FRAMES_PER_SECOND).ceil
      end

      # Whether the song at place +song+ of the ones held has a recording: every one held does.
      def song_held?(_song) = true

      private

      # What this copy holds for a chunk, or nil when it holds nothing there, or only a scrap.
      def recording(chunk)
        return unless chunk < @vswap.sound_count

        sound = @vswap.sound(chunk)
        sound if sound.length >= Sounds::SHORTEST_RECORDING
      end
    end

    # THE RECORDINGS AS THE PACK HOLDS THEM, every one in its room, with its length beside it.
    class Packed
      def initialize(build, pack)
        @b = build
        @pack = pack
      end

      # Every chunk of +chunks+ has a room in the pack.
      def sounds_held(chunks) = chunks.select { |chunk| chunk < SoundUnpacking::SOUNDS }

      def declare_sound_sample(name, chunk) = @b.sample(name, **sound_recording(chunk))

      # A note the length of the chunk's room, which runs on in silence past a shorter sound.
      def declare_sound_instrument(name, chunk)
        @b.instrument(name, **sound_recording(chunk))
        frames_of(SoundUnpacking::ROOM[chunk], Vswap::Sound::RATE)
      end

      # The sound's length in the pack, in frames, rounded as Baked rounds it.
      def sound_frames(chunk)
        ((sound_lengths[chunk] * AdlibSounds::FRAMES_PER_SECOND) + (Vswap::Sound::RATE / 2)) / Vswap::Sound::RATE
      end

      # A PLACE IN +chunks+, ROLLED AMONG THE ONES THIS COPY HAS, counted as the game plays: a roll of
      # ROLL_SPAN shared out among them, then the one it lands on found by walking the list. One past
      # the end, which names nothing, when the copy has none.
      def roll_held(chunks)
        Recordings.check_roll(chunks)
        @held_count ||= @b.var(:_recordings_held_count, 0)
        @held_left ||= @b.var(:_recordings_held_left, 0)
        @held_picked ||= @b.var(:_recordings_held_picked, 0)
        @held_count = 0
        chunks.each { |chunk| @held_count += 1 if sound_lengths[chunk] > 0 }
        @held_left = @b.rand(0...ROLL_SPAN) * @held_count / ROLL_SPAN
        @held_picked = chunks.length
        chunks.each_with_index do |chunk, place|
          if sound_lengths[chunk] > 0
            @held_picked = place if @held_left == 0
            @held_left -= 1
          end
        end
        @held_picked
      end

      # Every effect has a room in the pack, in AdlibUnpacking's order, which must be these.
      def adlib_held(numbers)
        unless numbers.values == AdlibUnpacking.numbers
          raise ArgumentError, "The pack holds the effects #{AdlibUnpacking.numbers.inspect}, not #{numbers.values.inspect}."
        end

        numbers
      end

      def declare_adlib_instrument(name, number)
        effect = AdlibUnpacking.numbers.index(number)
        @b.instrument(name, pcm: @pack[:adlib_samples].samples(AdlibUnpacking::EFFECT_AT[effect], AdlibUnpacking::ROOM[effect]),
                            rate: Opl2::RENDER_RATE, length: @pack[:adlib_length].number(effect))
        frames_of(AdlibUnpacking::ROOM[effect], Opl2::RENDER_RATE)
      end

      # Every effect is held, so no place names none.
      def adlib_note_frames(name, _numbers) = @b.table(name, @pack[:adlib_note_frames])
      def adlib_priorities(name, _numbers) = @b.table(name, @pack[:adlib_priority])

      # Every song has a room in the pack, in MusicUnpacking's order, which must be these.
      def songs_held(tracks)
        unless tracks == MusicUnpacking.numbers
          raise ArgumentError, "The pack holds the songs #{MusicUnpacking.numbers.inspect}, not #{tracks.inspect}."
        end

        tracks
      end

      def declare_song_instrument(name, track)
        song = MusicUnpacking.numbers.index(track)
        room = MusicUnpacking.rooms[song]
        @b.instrument(name, pcm: @pack[:music_samples].samples(MusicUnpacking.song_at[song], room),
                            rate: Opl2Track::COMPUTER_SAMPLE_RATE, length: @pack[:music_length].number(song))
        frames_of(room, Opl2Track::COMPUTER_SAMPLE_RATE)
      end

      # A song this copy lacks is nought long in the pack.
      def song_held?(song) = song_lengths[song] > 0

      private

      def sound_recording(chunk)
        { pcm: @pack[:sound_samples].samples(SoundUnpacking::SOUND_AT[chunk], SoundUnpacking::ROOM[chunk]),
          rate: Vswap::Sound::RATE, length: @pack[:sound_length].number(chunk) }
      end

      def frames_of(samples, rate) = ((samples.to_f / rate) * AdlibSounds::FRAMES_PER_SECOND).ceil

      def sound_lengths = @sound_lengths ||= @b.table(:sound_length, @pack[:sound_length])
      def song_lengths = @song_lengths ||= @b.table(:music_length, @pack[:music_length])
    end
  end
end
