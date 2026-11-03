# frozen_string_literal: true

module Wolf3D
  # THE MUSIC ON THE CARTRIDGE. Each track AdlibMusic reads is played through the chip while the
  # cartridge is built, so what ships is a long recording, and a song here is one note of it held
  # for its whole length. That way the framework streams it, loops it and keeps it in time, and the
  # game only ever says which song it wants.
  #
  # WHICH SONG IS WHICH is the original's: `songs` in wl_play.cpp for the floors, and wl_menu.h and
  # wl_inter.cpp for the rest. A track this copy does not hold names no song, and then the song that
  # was playing plays on.
  #
  # A RECORDING IS MADE ONCE. It takes seconds a track, so it is kept under tmp/, named for what it
  # was made from: the track's own writes and the code that plays them. It holds the game's own
  # music, so it is never committed.
  class Music
    # What the SOUND row can say. It is a number the sounds and the music both read, and its order
    # is the order the words are listed in.
    OFF = 0
    EFFECTS_ONLY = 1
    EFFECTS_AND_MUSIC = 2
    ROW_WORDS = ["SOUND: OFF", "SOUND: SFX ONLY", "SOUND: SFX + MUSIC"].freeze

    # The musicnames of audiowl6.h that are not in a floor's list.
    MENU_SONG = 14    # WONDERIN_MUS
    INTRO_SONG = 7    # NAZI_NOR_MUS
    BETWEEN_FLOORS_SONG = 16 # ENDLEVEL_MUS
    ROSTER_SONG = 23  # ROSTER_MUS
    WON_SONG = 24     # URAHERO_MUS

    GETTHEM = 3
    WARMARCH = 2
    SEARCHN = 11
    POW = 9
    SUSPENSE = 12
    CORNER = 0
    NAZI_OMI = 8
    PREGNANT = 18
    GOINGAFT = 17
    HEADACHE = 4
    DUNGEON = 1
    INTROCW3 = 6
    NAZI_RAP = 20
    TWELFTH = 22
    ZEROHOUR = 21
    ULTIMATE = 19
    PACMAN = 26
    FUNKYOU = 15

    FIRST_EPISODE = [GETTHEM, SEARCHN, POW, SUSPENSE, GETTHEM, SEARCHN, POW, SUSPENSE, WARMARCH, CORNER].freeze
    SECOND_EPISODE = [NAZI_OMI, PREGNANT, GOINGAFT, HEADACHE, NAZI_OMI, PREGNANT, HEADACHE, GOINGAFT, WARMARCH, DUNGEON].freeze
    THIRD_EPISODE = [INTROCW3, NAZI_RAP, TWELFTH, ZEROHOUR, INTROCW3, NAZI_RAP, TWELFTH, ZEROHOUR, ULTIMATE, PACMAN].freeze
    SIXTH_EPISODE = (THIRD_EPISODE[0...-1] + [FUNKYOU]).freeze

    # The song of each map of the game, by its place in GAMEMAPS.
    FLOOR_SONGS = Ractor.make_shareable(
      FIRST_EPISODE + SECOND_EPISODE + THIRD_EPISODE + FIRST_EPISODE + SECOND_EPISODE + SIXTH_EPISODE
    )

    # Kept below the effects' full level, so a shot is heard over the music.
    MUSIC_VOLUME = 11

    # At this tempo, and the twenty-four ticks to a beat a Score has unless it says otherwise, a
    # tick is one frame.
    FRAME_TICKS = 150

    # +tracks+ is the copy's AdlibMusic, or nil on a build with none, and then there is no music.
    # +setting+ is the variable the SOUND row moves. Sounds has turned sound on by now, since a copy
    # of the game with music has effects too.
    def initialize(build:, tracks:, floors:, setting:)
      @b = build
      @tracks = tracks
      @floors = floors
      @setting = setting
      # A computer has room for the music at the most a speaker takes; the console at less.
      @rate = build.built_for_computer? ? Opl2Track::COMPUTER_SAMPLE_RATE : Opl2Track::CONSOLE_SAMPLE_RATE
      declare
    end

    # WHERE A TRACK SITS IN THE LIST, for a table to hold. One this copy lacks lands past the end.
    def song_index(track) = @held.index(track) || @held.length

    # The song of the floor being played, by its place on the cartridge.
    def floor_song(floor) = @floor_songs ? @floor_songs[floor] : 0

    # SAYS WHICH SONG IS WANTED, every pass. Naming the one already playing changes nothing, and
    # stopping when nothing plays does nothing, so the SOUND row needs no more than this.
    def update(wanted)
      return if @songs.nil?

      if @setting == EFFECTS_AND_MUSIC
        @songs.play wanted
      else
        @songs.stop
      end
    end

    def stop = @songs&.stop

    private

    def declare
      others = [MENU_SONG, INTRO_SONG, BETWEEN_FLOORS_SONG, ROSTER_SONG, WON_SONG]
      wanted = (@floors.map { |floor| FLOOR_SONGS[floor.index] } + others).compact.uniq
      @held = @tracks ? wanted.reject { |track| @tracks.writes(track).empty? } : []
      return if @held.empty?

      @songs = @b.songs :music, @held.map { |track| score_of(track) }
      @floor_songs = @b.table :floor_song, @floors.map { |floor| song_index(FLOOR_SONGS[floor.index]) }, width: :byte
    end

    def score_of(track)
      pcm = @tracks.recording(track, rate: @rate)
      name = :"music_#{track}"
      @b.instrument name, pcm: pcm, rate: @rate
      frames = ((pcm.length.to_f / @rate) * AdlibSounds::FRAMES_PER_SECOND).ceil
      note = VBlank::Audio::Score::Note.new(at: 0, key: :C4, length: frames)
      VBlank::Audio::Score.new(
        tempo: FRAME_TICKS, parts: [VBlank::Audio::Score::Part.new(plays: name, volume: MUSIC_VOLUME, notes: [note])]
      )
    end
  end
end
