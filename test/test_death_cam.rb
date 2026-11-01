# frozen_string_literal: true

require_relative "test_helper"

# HOW A BOSS FLOOR ENDS WHEN THERE IS NO WAY OUT, read out of A_StartDeathCam (wl_act2.cpp).
#
# THE BOSS IS FINISHED OFF BY THE TEST, which no other test here does, and the reason is arithmetic:
# fifteen hundred hit points takes a chain gun most of a minute of frames, with him backing away and
# throwing things, and what is being tested starts once he is down. The game loop writes one number
# on one pass, and everything after that is the game's own.
class TestDeathCam < Minitest::Test
  include Wolf3DTest

  Enemy = Wolf3D::Enemy
  Cam = Wolf3D::DeathCam
  Release = Wolf3D::Fixture::Release
  Behaviour = Wolf3D::Behaviour

  ROW = 12
  PLAYER_X = 3
  BOSS_X = 6
  ONE = (1 << Fraction::DEFAULT_BITS).to_f

  # When the test's trigger is pulled, and the pass by which he has finished falling. The round leaves
  # the pistol a dozen passes after that, and five pictures and the body's twenty are about sixty.
  FIRED = 6
  DOWN = 80

  def test_the_body_lies_there_and_the_world_stops
    run = played(frames: DOWN)

    assert_equal Cam::FIRST_HOLD, run[:_cam_stage]
    assert_equal 1, run[:_cam_holding]
  end

  def test_then_the_game_says_lets_see_that_again
    run = played(frames: DOWN + Cam::HOLD + 2)

    assert_equal Cam::WORDS, run[:_cam_stage]
    assert_equal palette[Cam::GROUND], run.screen.pixel(2, 2), "the view has gone"
    refute_equal palette[Cam::GROUND], run.screen.pixel(2, Wolf3D::FirstPerson::VIEW_H), "and the bar stays"
  end

  # THE ANGLE IS THE ORIGINAL'S FROM WHERE YOU STOOD WHEN YOU KILLED HIM, not from where you walked to.
  def test_you_are_set_down_in_front_of_him_facing_him
    run = played(frames: words_gone, walking: true)
    boss_x = run.pool(:guard, :x).compact.first / ONE

    assert_equal Cam::REPLAY, run[:_cam_stage]
    assert_in_delta boss_x - Cam::FIRST_TRY, run[:px] / ONE, 0.01, "he fell east of the spot you shot from"
    assert_equal 0, run[:view], "so you look east"
  end

  def test_a_press_cuts_the_words_short
    run = played(frames: DOWN + Cam::HOLD + 12) { |f| f == DOWN + Cam::HOLD + 6 ? [:a] : [] }

    assert_equal Cam::REPLAY, run[:_cam_stage]
  end

  def test_he_falls_again_and_you_cannot_move
    run = played(frames: words_gone + 20) { |f| f > DOWN ? [:up] : [] }
    state = states.state_at(run.pool(:guard, :state).compact.first).name

    assert_match(/fall/, state.to_s, "he is falling again")
    assert_in_delta run.pool(:guard, :x).compact.first / ONE - Cam::FIRST_TRY, run[:px] / ONE, 0.01
  end

  def test_then_the_episode_is_over
    run = played(frames: words_gone + 80 + Cam::HOLD + 4)

    assert_equal 1, run[:episode_won]
    assert_equal 1, run[:game_over]
  end

  def test_nothing_hurts_you_while_you_watch
    run = played(frames: words_gone + 40, guards: { [14, ROW] => Wolf3D::Guards::STANDING })

    assert_equal Wolf3D::FirstPerson::START_HEALTH, run[:health]
  end

  def test_hans_has_no_death_cam
    %i[hans gretel mecha fake].each { |name| refute Enemy[name].ends_the_episode?, name }
    %i[schabbs gift fat hitler].each { |name| assert Enemy[name].ends_the_episode?, name }
  end

  def test_start_does_nothing_while_it_runs
    run = played(frames: DOWN + 8, menus: true) { |f| f == DOWN + 4 ? [:start] : [] }

    assert_equal Wolf3D::Menus::PLAYING, run[:screen]
  end

  private

  def states = Behaviour.for(%i[schabbs])

  # How long the words stay up when nobody presses anything, and a pass to line up.
  def words_gone = DOWN + Cam::HOLD + Cam::WORDS_FOR + 2

  # Stand the boss in front of the player, fire one shot at him on FIRED, and take him to one hit
  # point first so that it kills him.
  def played(frames:, walking: false, guards: {}, menus: false, &keys)
    script = keys || ->(f) { walking && f > DOWN - 40 ? [:l] : [] }
    Reference.new.input_each_frame { |f| f == FIRED ? [:b] + script.call(f) : script.call(f) }
             .run(program(guards, menus), frames: frames)
  end

  def program(guards, menus)
    @programs ||= {}
    @programs[[guards, menus]] ||= begin
      level = arena(side: 24, player: [PLAYER_X, ROW], things: { [BOSS_X, ROW] => Enemy[:schabbs].standing }.merge(guards))
      art = menus && Wolf3D::MenuArt.of(fixture.pictures)
      view_of(level) do |b, view, _|
        menus_on = art && Wolf3D::Menus.new(build: b, view: view, art: art, palette: Wolf3D::Palette.game,
                                            sound_on: b.var(:sound_on, 1), starting_on: Wolf3D::Menus::PLAYING)
        first = b.var :_test_first, 1
        game_loop do
          if first == 1
            first = 0
            view.guard_pool.pool.each { |guard| guard.hp = 1 }
          end
          art ? menus_on.update : view.update
        end
      end
    end
  end

  SPRITES = Enemy::ALL.flat_map(&:pictures).max + 1 + Wolf3D::WeaponAtlas::COUNT

  def fixture = @fixture ||= Release.new(set: "WL6", sprites: SPRITES, walls: (Wolf3D::Elevator::PULLED * 2) + 2)
end
