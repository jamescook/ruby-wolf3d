# frozen_string_literal: true

require_relative "test_helper"

# SAVE GAME AND LOAD GAME, from the menu, read out of CP_SaveGame, CP_LoadGame and DrawLoadSaveScreen
# (wl_menu.cpp). Played through the buttons, then the console turned off and on again by handing the
# same save memory to a second run.
class TestSavedGames < Minitest::Test
  include Wolf3DTest

  Menus = Wolf3D::Menus
  Saved = Wolf3D::SavedGames
  Release = Wolf3D::Fixture::Release

  ONE = (1 << Fraction::DEFAULT_BITS).to_f
  ROW = 8

  # PRESSES, by the pass each lands on. The menu's fades take a fifth of a second or so, and every
  # press here waits longer than that.
  OPEN_MENU = 60
  TO_SAVE_ROW = [75, 80].freeze
  PICK_SAVE = 90
  PICK_SLOT = 130
  SAVED_BY = 400
  TO_LOAD_SCREEN = { 2 => [:a], 6 => [:down], 10 => [:a] }.freeze

  def test_save_game_is_dim_until_a_game_is_on
    run = Reference.new.input_each_frame { |f| { 2 => [:a], 6 => [:down], 10 => [:down] }.fetch(f, []) }
                   .run(cartridge, frames: 14)

    assert_equal 3, run[:__menu_main], "down from Load Game steps over Save Game to Sound"
  end

  def test_with_nothing_saved_every_slot_says_empty
    run = Reference.new.input_each_frame { |f| TO_LOAD_SCREEN.fetch(f, []) }.run(cartridge, frames: 60)

    assert_equal Menus::LOADING, run[:screen]
    assert_equal [0] * Saved::SLOTS, (0...Saved::SLOTS).map { |n| run[:"_save_label_#{n}"] }
  end

  def test_picking_an_empty_slot_loads_nothing
    run = Reference.new.input_each_frame { |f| TO_LOAD_SCREEN.merge(60 => [:a]).fetch(f, []) }
                   .run(cartridge, frames: 90)

    assert_equal Menus::LOADING, run[:screen]
  end

  def test_b_goes_back_to_the_main_menu
    run = Reference.new.input_each_frame { |f| TO_LOAD_SCREEN.merge(60 => [:b]).fetch(f, []) }
                   .run(cartridge, frames: 110)

    assert_equal Menus::MENU, run[:screen]
  end

  def test_a_save_ends_at_the_main_menu
    assert_equal Menus::MENU, saved_game[0][:screen]
  end

  # IT SURVIVES THE POWER GOING OFF, and the slot says which episode and floor.
  def test_a_saved_slot_is_labelled_with_its_episode_and_floor
    run = power_on_and_open_load_screen

    assert_equal 1, run[:_save_label_0]
    assert_equal 1, run[:_save_episode_0]
    assert_equal 1, run[:_save_number_0]
    assert_equal 0, run[:_save_label_1]
  end

  def test_a_load_puts_you_back_where_you_saved
    before, image = saved_game
    run = Reference.new(save: image)
                   .input_each_frame { |f| TO_LOAD_SCREEN.merge(60 => [:a]).fetch(f, []) }
                   .run(cartridge(from: :notice), frames: 110)

    assert_equal Menus::PLAYING, run[:screen]
    assert_equal 1, run[:_in_game]
    assert_in_delta before[:px] / ONE, run[:px] / ONE, 0.001
    assert_equal before.pool(:guard, :hp).compact, run.pool(:guard, :hp).compact
  end

  # SAVING OVER A GAME ASKS FIRST (Confirm(GAMESVD)). B leaves the game that was there.
  def test_saving_over_a_game_asks_first
    run = over_a_saved_game(answer: [])

    assert_equal Menus::OVERWRITING, run[:screen]
  end

  def test_answering_no_goes_back_to_the_list
    run = over_a_saved_game(answer: [:b])

    assert_equal Menus::SAVING, run[:screen]
  end

  def test_answering_yes_saves_over_it
    run = over_a_saved_game(answer: [:a])

    assert_equal Menus::MENU, run[:screen]
  end

  # ON THE CONSOLE TOO: the save written by the real save routine, the power off, and a second
  # cartridge reading the same chip. Pressed for three frames each, since a pass here can take two.
  def test_a_save_survives_the_power_going_off_on_the_console
    backend = GBA.new
    rom = ROM.assemble(backend.lower(cartridge(from: :playing)), title: "SAVE")
    pressed = { 20 => Constants::KEY_START, 40 => Constants::KEY_DOWN, 50 => Constants::KEY_DOWN,
                60 => Constants::KEY_A, 100 => Constants::KEY_A }
    keys = ->(frame) { pressed.fetch(frame - (frame % 10), 0).then { |key| (frame % 10) < 3 ? key : 0 } }
    image = Verifier.new(rom, frames: 200, vars: backend.var_addresses, keys: keys).save_image

    again = GBA.new
    second = ROM.assemble(again.lower(cartridge(from: :load)), title: "SAVE")
    run = Verifier.new(second, frames: 40, vars: again.var_addresses, save: image)

    assert_equal Menus::LOADING, run.var(:screen)
    assert_equal 1, run.var(:_save_label_0), "the first slot holds a game"
  end

  def test_nothing_is_saved_without_being_asked
    image = SaveImage.new
    Reference.new(save: image).input_each_frame { [] }.run(cartridge(from: :playing), frames: 120)
    run = Reference.new(save: image).input_each_frame { |f| TO_LOAD_SCREEN.fetch(f, []) }
                   .run(cartridge(from: :notice), frames: 60)

    assert_equal 0, run[:_save_label_0]
  end

  private

  # A game played a little from the pause menu, saved in the first slot, written, and the memory.
  def saved_game
    Ractor.current[:saved_game_run] ||= begin
      image = SaveImage.new
      run = Reference.new(save: image).input_each_frame { |f| save_presses(f) }
                     .run(cartridge(from: :playing), frames: SAVED_BY)
      [run, image]
    end
  end

  def save_presses(pass)
    return [:start] if pass == OPEN_MENU
    return [:down] if TO_SAVE_ROW.include?(pass)

    [PICK_SAVE, PICK_SLOT].include?(pass) ? [:a] : [:up].take(pass < OPEN_MENU ? 1 : 0)
  end

  def power_on_and_open_load_screen
    Reference.new(save: saved_game[1])
             .input_each_frame { |f| TO_LOAD_SCREEN.fetch(f, []) }
             .run(cartridge(from: :notice), frames: 60)
  end

  # The same save over again, onto the slot it has already filled.
  def over_a_saved_game(answer:)
    image = saved_game[1].dup
    presses = lambda do |pass|
      next answer if pass == PICK_SLOT + 40
      save_presses(pass)
    end
    Reference.new(save: image).input_each_frame(&presses).run(cartridge(from: :playing), frames: PICK_SLOT + 60)
  end

  def fixture = @fixture ||= Release.new(set: "WL6", walls: (Wolf3D::Elevator::PULLED * 2) + 2)

  def cartridge(from: :notice)
    Ractor.current[:"saved_games_#{from}"] ||= begin
      art = Wolf3D::MenuArt.of(fixture.pictures)
      screen = { playing: Menus::PLAYING, notice: Menus::NOTICE, load: Menus::LOADING }.fetch(from)
      view_of(arena(side: 24, player: [3, ROW], guards: [[20, ROW, :north]]), sound: 1) do |b, view, sound_on|
        menus = Menus.new(build: b, view: view, art: art, palette: Wolf3D::Palette.game, sound_on: sound_on,
                          starting_on: screen)
        b.game_loop { menus.update }
      end
    end
  end
end
