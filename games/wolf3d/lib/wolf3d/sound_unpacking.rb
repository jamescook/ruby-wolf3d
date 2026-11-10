# frozen_string_literal: true

module Wolf3D
  # THE RECORDED SOUNDS OF VSWAP, COPIED BY THE GAME ITSELF into the data pack (DataPack): the guns,
  # the guards, the doors, what Sounds makes into samples for a trimmed build (Vswap#sound).
  #
  # Kept as VSWAP keeps them, eight bits a sample at seven thousand a second with silence at 128
  # (Vswap::Sound), so the pack holds the original's own bytes. Each sound has a room of its own in
  # sound_samples, ROOM long, at SOUND_AT; what a sound leaves of its room is silence; and its own
  # length is in sound_length.
  #
  # WHERE A SOUND IS: VSWAP's last page is an index of the sounds, a word for the page each starts on
  # (counted from the first sound's page) and a word for its length in bytes. A sound longer than a
  # page runs on over the pages after it, each page wherever VSWAP's header puts it (wolf4sdl:
  # id_pm.cpp, PM_Startup and the DigiList it reads; Wolf3D::Vswap#sound reads the same).
  #
  # AN EMPTY PAGE IS STEPPED OVER, not the end of the sound. The shareware keeps the pages of the
  # sounds it does not ship, each nought long, and the original keeps every page one after another
  # in memory, so a sound starting on one runs on into whatever page next holds bytes: the next
  # sound the shareware ships, or at the last the index itself (its 184-byte scraps).
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and every count is a variable of the routine's (#routine_var).
  class SoundUnpacking
    # EACH SOUND'S ROOM, in bytes: the longest that sound runs in any release this game reads,
    # counted off the copies (the index says them; the original's source does not). The six
    # episodes' are the longer of the two everywhere; the shareware's sounds it does not ship are
    # scraps of 184 bytes. Spear keeps other sounds and will want a list of its own.
    ROOM = [5996, 3793, 19_995, 10_022, 3600, 3605, 4065, 4495, 6334, 5781, 10_716, 5410, 2850, 3750, 2215,
            24_763, 3057, 5632, 10_949, 13_866, 5874, 8815, 9095, 5689, 24_577, 13_206, 14_849, 5137, 8346,
            4437, 4568, 5349, 7002, 7024, 7604, 4344, 9544, 17_448, 24_372, 3030, 6300, 5244, 6809, 8562,
            11_048, 12_499].freeze
    SOUNDS = ROOM.length

    # Where each sound's room starts in sound_samples.
    SOUND_AT = ROOM.each_with_object([0]) { |room, starts| starts << (starts.last + room) }.first(SOUNDS).freeze

    SILENCE = Vswap::Sound::MIDPOINT

    # The slots the sounds take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :sound_samples, count: ROOM.sum, width: :byte, signed: false
      slots.numbers :sound_length, count: SOUNDS, width: :half, signed: false
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      @vswap = @copy.file("VSWAP.#{@release}")
      @rooms = @b.table(:sound_room, ROOM, width: :half)
      @sound_at = @b.table(:sound_at, SOUND_AT, width: :word)
      routine_var(:pages).store!(@vswap.half(0))
      routine_var(:first_sound).store!(@vswap.half(4))
      read_page(routine_var(:pages) - 1)
      routine_var(:index_at).store!(routine_var(:page_start))
      routine_var(:index_length).store!(routine_var(:page_length))
      routine_var(:index_inside).store!(0)
      routine_var(:index_inside).store!(1) if routine_var(:index_at) + routine_var(:index_length) <= @vswap.size
      @b.repeat(SOUNDS) { |sound| copy_sound(sound) }
    end

    private

    # SOUND +sound+ into its room, if the index names it, one page after another until it is whole
    # or VSWAP's pages run out; then silence to the end of the room. A page outside VSWAP ends the
    # sound where it got to. Every turn of the loop moves on a page or ends it, so it ends.
    def copy_sound(sound)
      written = routine_var(:written)
      length = routine_var(:length)
      done = routine_var(:done)
      room = routine_var(:room)
      room.store!(@rooms[sound])
      written.store!(0)
      length.store!(0)
      named = routine_var(:named)
      named.store!(0)
      named.store!(1) if routine_var(:index_inside) == 1 && (4 * sound) + 4 <= routine_var(:index_length)
      if named == 1
        routine_var(:page).store!(routine_var(:first_sound) + @vswap.half(routine_var(:index_at) + (4 * sound)))
        length.store!(@vswap.half(routine_var(:index_at) + (4 * sound) + 2))
        length.store!(room) if length > room
      end
      done.store!(0)
      done.store!(1) if written >= length
      while done == 0
        copy_page(sound)
        done.store!(1) if (written >= length) | (routine_var(:page) >= routine_var(:pages))
      end
      @pack[:sound_length][sound] = written
      fill_silence(sound)
    end

    # The next page of the sound into its room: as much of it as the sound has left, from where the
    # sound has got to. A page outside VSWAP ends the sound.
    def copy_page(sound)
      written = routine_var(:written)
      take = routine_var(:take)
      read_page(routine_var(:page))
      take.store!(routine_var(:length) - written)
      take.store!(routine_var(:page_length)) if routine_var(:page_length) < take
      inside = routine_var(:inside)
      inside.store!(0)
      inside.store!(1) if routine_var(:page) < routine_var(:pages) && routine_var(:page_start) + take <= @vswap.size
      if inside == 1
        if take > 0
          @vswap.copy_bytes at: routine_var(:page_start), count: take, into: @pack[:sound_samples],
                            start: @sound_at[sound] + written
        end
        written.store!(written + take)
        routine_var(:page).store!(routine_var(:page) + 1)
      else
        routine_var(:done).store!(1)
      end
    end

    # Silence from where the sound ended to the end of its room.
    def fill_silence(sound)
      at = routine_var(:silent_at)
      at.store!(routine_var(:written))
      @copy.count_written routine_var(:room) - at
      while at < routine_var(:room)
        @pack[:sound_samples][@sound_at[sound] + at] = SILENCE
        at.store!(at + 1)
      end
    end

    # Where page +page+ starts in VSWAP, into page_start, and how long it is, into page_length.
    def read_page(page)
      routine_var(:page_start).store!(@vswap.word(Vswap::HEADER_BYTES + (4 * page)))
      routine_var(:page_length).store!(@vswap.half(Vswap::HEADER_BYTES + (4 * routine_var(:pages)) + (2 * page)))
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_sound_unpacking_#{name}", 0)
  end
end
