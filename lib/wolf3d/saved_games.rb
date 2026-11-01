# frozen_string_literal: true

module Wolf3D
  # THE GAMES SAVED ON THE CARTRIDGE, and nothing about the screens you reach them from. The original
  # keeps ten, and a save is the whole world at that moment (SaveTheGame, wl_main.cpp). It never saves
  # on its own, so turning the console off loses everything since the last one.
  #
  # A SLOT IS LABELLED WITH ITS EPISODE AND FLOOR, where the original has you type a name: a console
  # with no keyboard has nothing to type on. What a slot holds is read straight out of the save, so a
  # label can never disagree with what loading it would give you.
  class SavedGames
    # SEVEN, WHERE THE ORIGINAL HAS TEN, and it is the console's limit. The busiest floor decides how
    # big a save is, every save is kept twice so a power cut cannot lose it, and each of the two
    # takes whole 4K blocks of the largest save memory a cartridge can have, which is 128K. The build
    # refuses any more than this.
    SLOTS = 7

    # WHAT A ROW SAYS, nothing saved there or a game. Words are painted into the code, one copy for
    # each row and each thing it can say, so the episode and the floor are numbers drawn into the gaps
    # rather than a row saying each of the sixty floors.
    EPISODE = "Episode"
    FLOOR = ",  floor"
    LABELS = Ractor.make_shareable(["- empty -", "#{EPISODE} #{FLOOR}"])

    def initialize(build:, view:)
      @b = build
      @view = view
      @playthrough = view.playthrough
      floors = view.floors
      @record = @b.save_data :game, copies: SLOTS, fast: false
      view.lasting.keep_in(@record)
      # A cartridge with nobody on it rolls no dice, and the framework refuses to be told to leave
      # out what is not there.
      left_out = LastingState::LEFT_OUT.keys
      left_out -= [:random_numbers] if floors.no_floor_has?(:guards)
      @b.saves_keep_everything except: left_out
      @episode_of = @b.table :save_episode, floors.map { |f| (f.index / Floors::PER_EPISODE) + 1 }, width: :byte
      @number_of = @b.table :save_floor_number, floors.map { |f| (f.index % Floors::PER_EPISODE) + 1 }, width: :byte
      @labels = (0...SLOTS).map { |n| @b.var :"_save_label_#{n}", 0 }
      @episodes = (0...SLOTS).map { |n| @b.var :"_save_episode_#{n}", 0 }
      @numbers = (0...SLOTS).map { |n| @b.var :"_save_number_#{n}", 0 }
      @slot = @b.var :_save_slot, 0
    end

    # Which of LABELS slot +n+ says, and the two numbers that go in its gaps.
    def label_variable(n) = @labels[n]
    def episode_variable(n) = @episodes[n]
    def number_variable(n) = @numbers[n]

    # READ WHAT EVERY SLOT HOLDS, for a screen that lists them. The list is read each pass rather
    # than remembered, because reading a slot finishes any save still being written to it.
    def refresh_labels
      (0...SLOTS).each do |n|
        hands = { label: @labels[n], episode: @episodes[n], number: @numbers[n] }
        hands[:label] = 0
        if @record[n].good?
          hands[:label] = 1
          hands[:episode] = @episode_of[@record[n].peek(@playthrough.floor)]
          hands[:number] = @number_of[@record[n].peek(@playthrough.floor)]
        end
      end
    end

    # Does slot +n+ hold a game?
    def occupied?(n) = @labels[n] != 0

    # WHICH SLOT A SAVE IS HEADED FOR, held while the game asks whether to write over it.
    def choose_slot(n)
      @slot = n
    end

    def write_chosen_slot = @record[@slot].save

    # A GAME COMES BACK and every table is pointed at its floor again, as LoadTheGame does.
    def load_slot(n)
      @record[n].load
      @playthrough.start(:resume)
    end
  end
end
