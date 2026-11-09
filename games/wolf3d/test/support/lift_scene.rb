# frozen_string_literal: true

module Wolf3DTest
  # THE FIRST FLOOR'S SECRET LIFT, ridden: the player is put down in its car facing a lever, pulls it,
  # and the screen between floors comes up in the big letters. test_holding.rb holds the lift and the
  # lettering of a whole build to a trimmed one, and films/whole_tally.rb shows it.
  module LiftScene
    PULL_FRAME = 70 # After the floor has faded in
    PULLED_FRAMES = 80 # ...long enough after the pull to read which lift it was
    # ...long enough for the lift to be in and the screen between floors up.
    TALLY_FRAMES = PULL_FRAME + Wolf3D::FirstPerson::LIFT_WAIT + 40
    # ...and for its figures to count up, for the film.
    FILM_FRAMES = 400

    # The buttons down on +frame+, counted from one.
    def self.keys(frame) = frame == PULL_FRAME ? [:a] : []

    # WOLF3D_START's x,y,facing for the first floor's secret car (Elevator#secret_cars), facing a
    # lever beside it east or west: a lever is pulled only along the east-west axis
    # (FirstPerson#pull_the_lever, the original's Cmd_Use).
    def self.start
      level = Wolf3D.maps[0]
      car = Wolf3D::Elevator.new(level).secret_cars.first
      x = car % level.width
      y = car / level.width
      facing = { [-1, 0] => :west, [1, 0] => :east }
      _, face = facing.find { |(dx, dy), _| level.wall_code(x + dx, y + dy) == Wolf3D::Elevator::SWITCH }
      "#{x},#{y},#{face}"
    end
  end
end
