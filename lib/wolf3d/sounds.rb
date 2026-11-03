# frozen_string_literal: true

module Wolf3D
  # THE SOUNDS THE GAME MAKES: the pistol, the guards shouting and shooting and dying, the doors,
  # the wall that slides away.
  #
  # These are the ones Wolfenstein RECORDED. They sit in VSWAP as raw 8-bit samples at about
  # seven thousand a second, which is exactly what the framework's `sample` verb takes — so the
  # whole of the conversion is taking 128 off every byte, which Vswap::Sound already does. No
  # file format, no resampling, nothing to install.
  #
  # THE OTHER HALF ARE ADLIB EFFECTS: walking into a wall, picking something up, a locked door, the
  # knife, the player's own death and the screen between floors. Those are recipes for a synthesiser
  # chip. Opl2 plays each one while the cartridge is built, and here it is a recording like any other.
  # See #declare_adlib_effects.
  #
  # WHICH CHUNK IS WHICH is the original's own table (wl_main.cpp, wolfdigimap) rather than
  # remembered. It maps a sound the game asks for onto a numbered chunk of VSWAP, and the numbers
  # below are that map for the sounds this game can currently make.
  #
  # A COPY OF THE GAME MAY NOT HAVE ALL OF THEM. The shareware release ships fewer chunks than the
  # registered one — the map above is `#ifndef UPLOAD` in places — so every sound here is looked
  # up against what the player's own file actually holds, and one that is not there is simply
  # never played. Nothing is a build error: a floor that is quieter than it might be is better
  # than a cartridge that will not build.
  class Sounds
    # The player's own guns. Three of the four are recordings. The knife is an AdLib effect.
    MACHINE_GUN = 4
    PISTOL = 5
    CHAIN_GUN = 6        # the gatling gun, as the original's own art calls it
    GUNS = [PISTOL, MACHINE_GUN, CHAIN_GUN].freeze
    NOTICES_YOU = 0     # "Halt!" — a guard the moment he sees you
    GUARD_FIRES = 21     # ...and his gun
    SLURP = 22           # Hitler going down, and what is left of somebody being eaten
    YEAH = 32            # BJ, jumping for joy
    MACHINE_TREAD = 31   # the machine's footfall
    DOG_BITES = 29
    DOOR_OPENS = 3
    DOOR_SHUTS = 2
    SECRET_WALL = 15     # a wall that slides away
    # The lift starting, when you pull the lever at the end of a floor. This one is NOT in the
    # shareware release — the original's map has it behind the same switch that hides the later
    # episodes' sounds — so a shareware copy simply plays nothing here, like every other sound
    # it does not hold.
    LEVEL_DONE = 30

    # A GUARD HAS EIGHT DEATH SCREAMS and the original picks between them at random, which is what
    # stops a firefight sounding like a loop. Two of them are in every copy of the game and the
    # rest come with the registered one; whichever are there get used.
    #
    # The first two are the original's own first three — its map points two of them at the same
    # chunk, so there are seven recordings of the eight. Its sixth is RARE_SCREAM.
    DEATH_SCREAMS = [12, 13, 34, 35, 40, 41, 42].freeze

    # THE ONE IT KEEPS BACK for the tenth floor of an episode (A_DeathScream). The original's map
    # calls it FART, and it comes one fall in 256 from anyone there but a boss.
    RARE_SCREAM = 39

    # WHAT EACH KIND SAYS. Each of these is the original's: who shouts what on seeing you is
    # FirstSighting (wl_state.cpp), who fires what is T_Shoot (wl_act2.cpp), and who dies how is
    # A_DeathScream. The numbers are wolfdigimap's. A kind not named makes no sound there, or one of
    # the AdLib effects, which is the same thing here: a mutant has seen you in silence.
    SIGHTING = Ractor.make_shareable({ guard: NOTICES_YOU, officer: 27, ss: 7, dog: 1, hans: 8, gretel: 43,
                                       gift: 37, fat: 38, schabbs: 25, fake: 23, mecha: 18, hitler: 18 })
    FIRING = Ractor.make_shareable({ guard: GUARD_FIRES, officer: GUARD_FIRES, mutant: GUARD_FIRES,
                                     gretel: GUARD_FIRES, ss: 11, hans: 10, mecha: 10, hitler: 10 })
    # +guard: :a_scream+ is one rolled from DEATH_SCREAMS.
    DYING = Ractor.make_shareable({ guard: :a_scream, mutant: 17, officer: 28, ss: 20, dog: 16, hans: 9,
                                    gretel: 44, schabbs: 24, fake: 26, mecha: 33, hitler: 19, gift: 36,
                                    fat: 45 })

    # THE SHAREWARE KEEPS THE SLOTS OF THE SOUNDS IT LEFT OUT, each holding the same scrap of a few
    # bytes. Played, that is a click, so anything this short is a sound this copy does not have. The
    # shortest real one runs to about a third of a second.
    SHORTEST_RECORDING = 256

    # THE ADLIB EFFECTS THIS GAME PLAYS, by the numbers of audiowl6.h and where wl_agent.cpp,
    # wl_act1.cpp, wl_game.cpp and wl_inter.cpp play them.
    ADLIB_EFFECT_NUMBERS = Ractor.make_shareable({ hit_wall: 0, no_way: 6, player_death: 9, key: 12, knife: 23, machine_gun: 30,
                                    ammo: 31, food: 33, first_aid: 34, cross: 35, chalice: 36, bible: 37,
                                    chain_gun: 38, end_bonus1: 42, end_bonus2: 43, one_up: 44, crown: 45,
                                    no_bonus: 47, percent100: 48 })

    # +vswap+ is the player's own copy of the game's sounds, or nil on a build with no data,
    # which makes every one of these do nothing. +adlib+ is its AdlibSounds, and nil leaves those
    # effects out. +switch+ is a variable that is nought while sound is off — the menu's own SOUND
    # row moves it — or nil on a cartridge with no way to turn sound off, and then nothing is tested.
    # +kinds+ names who is on this cartridge to be heard.
    def initialize(build:, vswap: nil, adlib: nil, switch: nil, kinds: [:guard])
      @b = build
      @vswap = vswap
      @adlib = adlib
      @switch = switch
      @kinds = kinds
      declare
    end

    # WHERE AN ADLIB EFFECT SITS IN THE LIST, for a table to hold. One this copy does not hold lands
    # past the end, and a number naming no effect plays nothing.
    def adlib_number(name) = @adlib_names.index(name) || @adlib_names.length

    # ...and the effect itself, by name, and by a number the game read from a table.
    def play_adlib_named(name)
      play_adlib_number(adlib_number(name)) if @adlib_names.include?(name)
    end

    def play_adlib_number(number)
      return if @adlib_effects.nil?

      @adlib_asked = number
      @b.call :play_adlib
    end

    # THE WALL IS HEARD ONLY OVER SILENCE (ClipMove: `if (!SD_SoundPlaying())`), which is why walking
    # along a wall scrapes rather than hammering, and why a wall never cuts a pickup off.
    def play_hit_wall
      @b.call :play_hit_wall if @adlib_effects
    end

    # THE COUNT OF WHETHER AN ADLIB EFFECT IS STILL SOUNDING, by the frame so that a slow pass does not
    # stretch it, and on every pass of the game so that a death or the tally does not hold it.
    def update
      return if @adlib_effects.nil?

      @b.once_a_frame(:count_adlib_frames) { @adlib_frames_left -= 1 if @adlib_frames_left > 0 }
    end

    # THE GUN GOES OFF, and the shot before it is cut off, whichever gun fired that one. +number+
    # counts the guns from the pistol and the game works it out, so the gun in your hands picks
    # its own recording without a branch per gun. See #declare_the_guns for how.
    def gun(number)
      return if @guns.nil?

      when_sound_is_on { @guns.play @gun_effect[number] }
    end

    # WHERE +chunk+ SITS IN THE LIST OF VOICES, for a table to hold. A chunk this copy does not hold,
    # or nil for no sound, lands past the end, and a number naming no effect plays nothing.
    def voice(chunk)
      return @voice_count + 1 if chunk == :a_scream

      @held_voices.index(chunk) || @voice_count
    end

    # THE ONE A TABLE NAMED, which is how a state number picks what is heard without a test per kind.
    def say(number)
      return if @voices.nil?

      when_sound_is_on { @voices.play number }
    end

    # ...and the same for a death, where the one number that is not a voice rolls a scream.
    def dies(number)
      if number == @voice_count + 1
        a_guard_dies
      else
        say(number)
      end
    end

    def bites = say_chunk(DOG_BITES)
    def tread = say_chunk(MACHINE_TREAD)
    def slurp = say_chunk(SLURP)
    def rare_scream = say_chunk(RARE_SCREAM)
    def yeah = say_chunk(YEAH)

    # A number written into the game has to name a sound the list holds, so one this copy lacks is
    # not asked for at all.
    def say_chunk(chunk)
      say(voice(chunk)) if @held_voices.include?(chunk)
    end

    def door_opens = retrigger(DOOR_OPENS)
    def door_shuts = retrigger(DOOR_SHUTS)
    def secret_wall = retrigger(SECRET_WALL)
    def level_done = play(LEVEL_DONE)

    # How long that one lasts, in frames, which the lift needs: the original plays it and then
    # WAITS for it to finish before the floor ends, so the sound is what decides the pause. Nil
    # when this copy of the game does not hold the recording.
    def level_done_frames
      sound = @clips_source&.[](LEVEL_DONE) or return nil

      ((sound.pcm.length.to_f / sound.rate) * 60).round
    end

    # ...and one of his death screams, picked by a number the game rolls. See #declare_the_screams.
    def a_guard_dies
      return if @screams.nil?

      when_sound_is_on { @screams.play(@scream_count == 1 ? 0 : @b.rand(0...@scream_count)) }
    end

    private

    # EVERY SOUND GOES THROUGH HERE, so the one row on the menu that turns sound off turns off
    # all of it. A cartridge with no such row has nothing to test and simply plays.
    def when_sound_is_on
      return yield if @switch.nil?

      yield if @switch != Music::OFF
    end

    # Every chunk this game plays as a sample. Named for the moment rather than the number, so a
    # sound the player's copy does not hold simply never reaches the list. The guns and the screams
    # are not here, nor anything an enemy says: see #declare_the_guns, #declare_the_screams and
    # #declare_the_voices.
    WANTED = [DOOR_OPENS, DOOR_SHUTS, SECRET_WALL, LEVEL_DONE].freeze

    # At this tempo, and the twenty-four ticks to a beat a Score has unless it says otherwise, a
    # tick is one frame.
    FRAME_TICKS = 150

    # The loudest a part can play, which is the level a sample plays at unless told otherwise, so
    # a gun is no quieter for being an effect.
    FULL = 15

    def declare
      @clips = {}
      # The recordings themselves, kept beside the clips because how LONG one lasts is a question
      # a caller can ask and a built clip cannot answer.
      @clips_source = {}
      @held_voices = []
      @voice_count = 0
      @adlib_names = []
      declare_adlib_effects
      return if @vswap.nil?

      WANTED.uniq.each do |chunk|
        sound = recording(chunk) or next

        @clips_source[chunk] = sound
        @clips[chunk] = @b.sample(:"sound_#{chunk}", pcm: sound.pcm, rate: sound.rate)
      end
      @b.enable_sound if @adlib_effects.nil? && (GUNS + DEATH_SCREAMS + voices_wanted).any? { |chunk| recording(chunk) }
      declare_the_guns
      declare_the_screams
      declare_the_voices
    end

    # THE CHIP HAS ONE VOICE FOR THESE, so a group is what they are: one at a time, and a sound of at
    # least the priority of the one playing replaces it, or is not played (SD_PlaySound). That
    # priority is the file's own. They rank among themselves and do not touch a recording, because
    # the original plays those on the mixer beside the chip.
    #
    # WHAT COUNTS AS STILL SOUNDING IS THE NOTES AND NOT THE FADE AFTER THEM, because that is when the
    # original clears its own count. The tables are of the effects' numbers in the list here, and
    # each has one more row, for the place that names no effect.
    def declare_adlib_effects
      return if @adlib.nil?

      held = ADLIB_EFFECT_NUMBERS.select { |_, number| @adlib.recording(number) }
      return if held.empty?

      @adlib_names = held.keys
      recordings = held.values.map { |number| @adlib.recording(number) }
      priorities = held.map { |name, number| adlib_priority(name, @adlib.recording(number)) }
      @b.enable_sound
      @adlib_effects = @b.sound_effects :adlib, held.values.each_with_index.map { |number, n| adlib_score(recordings[n], number, priorities[n]) }
      @adlib_frames = @b.table :adlib_frames, recordings.map(&:note_frames) + [0], width: :half
      @adlib_priorities = @b.table :adlib_priorities, priorities + [0], width: :byte
      @adlib_frames_left = @b.var :_adlib_frames_left, 0
      @adlib_priority_sounding = @b.var :_adlib_priority_sounding, 0
      @adlib_asked = @b.var :_adlib_asked, 0
      @b.func(:play_adlib, fast: false) { when_sound_is_on { start_adlib_if_allowed } }
      @b.func(:play_hit_wall, fast: false) { play_adlib_named(:hit_wall) if @adlib_frames_left == 0 }
    end

    # The same test the group makes, so a sound it refuses does not move the count.
    def start_adlib_if_allowed
      if @adlib_frames_left == 0 || @adlib_priorities[@adlib_asked] >= @adlib_priority_sounding
        @adlib_effects.play @adlib_asked
        @adlib_frames_left = @adlib_frames[@adlib_asked]
        @adlib_priority_sounding = @adlib_priorities[@adlib_asked]
      end
    end

    # THE TALLY'S SOUNDS RANK LEVEL. The original stops a sound and waits for each before going on,
    # and here the figures do not wait, so a high one left over from one row would silence the next.
    # At one level the last asked for wins.
    TALLY_EFFECTS = %i[end_bonus1 end_bonus2 no_bonus percent100].freeze
    TALLY_PRIORITY = 60

    def adlib_priority(name, recording) = TALLY_EFFECTS.include?(name) ? TALLY_PRIORITY : recording.priority

    def adlib_score(recording, number, priority)
      @b.instrument :"adlib_#{number}", pcm: recording.pcm, rate: recording.rate
      note = VBlank::Audio::Score::Note.new(at: 0, key: :C4, length: recording.sample_frames)
      VBlank::Audio::Score.new(
        tempo: FRAME_TICKS, group: :adlib, priority: priority,
        parts: [VBlank::Audio::Score::Part.new(plays: :"adlib_#{number}", volume: FULL, notes: [note])]
      )
    end

    # EVERYTHING THE KINDS ON THIS CARTRIDGE SAY, in one list, so a table can name any of them by
    # number and a kind costs a column rather than a test. Like the screams, these are heard over
    # each other, and a cartridge pays only for the recordings of who is on it.
    def declare_the_voices
      @held_voices = voices_wanted.select { |chunk| recording(chunk) }
      @voice_count = @held_voices.length
      return if @held_voices.empty?

      @voices = @b.sound_effects :voices, @held_voices.map { |chunk| recording_as_effect(chunk) }
    end

    def voices_wanted
      said = @kinds.flat_map { |kind| [SIGHTING[kind], FIRING[kind], DYING[kind]] }
      said += [DOG_BITES] if @kinds.include?(:dog)
      said += [MACHINE_TREAD] if @kinds.include?(:mecha)
      said += [SLURP, RARE_SCREAM, YEAH]
      said.compact.uniq - [:a_scream]
    end

    # What this copy holds for a chunk, or nil when it holds nothing there.
    def recording(chunk)
      return unless chunk < @vswap.sound_count

      sound = @vswap.sound(chunk)
      sound if sound.length >= SHORTEST_RECORDING
    end

    # THE ORIGINAL GIVES THE PLAYER'S WEAPONS ONE MIXER CHANNEL. Its map of digitised sounds
    # (wl_main.cpp, wolfdigimap) says which channel each recording plays on, and all three guns
    # name channel 0, kept for them alone. So a new shot from any gun cuts off the last shot from
    # any gun, and the last one asked for wins. Without that, tapping the trigger fills every
    # voice with pistol and there is none left for anything else.
    #
    # A GROUP OF SOUND EFFECTS IS THAT CHANNEL: its effects play one at a time, and at equal
    # priority the one asked for last wins. An effect is a Score, and a Score plays notes, so each
    # recording becomes an instrument and each shot one note at the recording's own pitch, long
    # enough to let it run out. An effect also starts a frame after it is asked for, which nobody
    # hears under a pass of several frames.
    #
    # THE PLAYER'S SHOT NOW OUTRANKS A GUARD'S SHOUT when the mixer runs out of voices, because the
    # game's samples rank below every effect. That is right for a game whose original keeps a
    # channel for that shot.
    #
    # A GUN THIS COPY DOES NOT HOLD IS LEFT OUT OF THE LIST, which moves the numbers of the guns
    # after it, so the table says where each gun landed. One that is missing points just past the
    # end, and a number naming no effect plays nothing.
    def declare_the_guns
      held = GUNS.select { |chunk| recording(chunk) }
      return if held.empty?

      @guns = @b.sound_effects :guns, held.map { |chunk| recording_as_effect(chunk, group: :player_weapon) }
      @gun_effect = @b.table :gun_effect, GUNS.map { |chunk| held.index(chunk) || held.length }, width: :byte
    end

    # THE SCREAMS ARE A LIST OF THE ONES THIS COPY HOLDS, so a rolled number names one directly and
    # there is no test per scream. A copy with none has no list, and a guard falls silently.
    #
    # THE ORIGINAL STACKS THESE: every scream in its map is channel -1, any free one. Here they are
    # in no group, so two different screams overlap as they do there. The one difference is the
    # same scream twice at once: an effect asked for again while it sounds starts again, so the
    # first is cut off, where the original would sound both. We take that, because the second
    # scream covers the first anyway and two copies of one recording only read as a louder one. A
    # chain gun into a room of guards on the shareware, which holds only two screams, sounds right
    # by ear: the cut-off is not heard.
    #
    # A SCREAM NOW OUTRANKS A GUARD'S SHOUT OR SHOT when the mixer runs out of voices, because the
    # game's samples rank below every effect. It also starts a frame after it is asked for.
    def declare_the_screams
      held = DEATH_SCREAMS.select { |chunk| recording(chunk) }
      return if held.empty?

      @screams = @b.sound_effects :screams, held.map { |chunk| recording_as_effect(chunk) }
      @scream_count = held.length
    end

    def recording_as_effect(chunk, group: nil)
      sound = recording(chunk)
      @b.instrument :"sound_#{chunk}", pcm: sound.pcm, rate: sound.rate
      frames = ((sound.pcm.length.to_f / sound.rate) * 60).ceil
      note = VBlank::Audio::Score::Note.new(at: 0, key: :C4, length: frames)

      VBlank::Audio::Score.new(
        tempo: FRAME_TICKS, group: group,
        parts: [VBlank::Audio::Score::Part.new(plays: :"sound_#{chunk}", volume: FULL, notes: [note])]
      )
    end

    def play(chunk)
      clip = @clips[chunk] or return

      when_sound_is_on { clip.play }
    end

    # Cut whatever of this sound is still going and start it again, for the sounds one thing makes
    # over and over.
    def retrigger(chunk)
      clip = @clips[chunk] or return

      when_sound_is_on do
        clip.stop
        clip.play
      end
    end
  end
end
