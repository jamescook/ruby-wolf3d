# frozen_string_literal: true

module Wolf3DTest
  # THE FIRST FLOOR'S FIRST GUARD SHOT, which is most of what the game sounds like at once: the
  # player is put down two cells south of him, facing him, and fires a press every few frames until
  # he falls, his shout, his gun and his scream over the pistol and the floor's song.
  # e2e/test_whole_builds.rb holds a whole build's sound to a trimmed one's here, and
  # films/whole_sounds.rb plays both.
  module ShotGuardScene
    STANDING_FRAMES = 59
    FRAMES = 220

    # The settings that put the player there, on the first floor of +level+ (a Level), the first
    # floor of the copy in use.
    def self.settings(level)
      guard = first_guard_with_room_south(level)
      { floors: 1, screen: "playing", start: "#{guard.x},#{guard.y + 2},north" }
    end

    # The buttons down on +frame+, counted from one.
    def self.keys(frame) = frame > STANDING_FRAMES && (frame % 12).zero? ? [:b] : []

    # +level+'s first guard standing on every setting, with two empty cells south of him.
    def self.first_guard_with_room_south(level)
      Wolf3D::Guards.new(level).at(:baby).find do |g|
        g.kind == :guard && [1, 2].all? { |down| empty_floor?(level, g.x, g.y + down) }
      end
    end

    # Floor with nothing on it: no piece, no guard, no start (Level#starting_at refuses the rest).
    def self.empty_floor?(level, x, y) = !level.solid?(x, y) && level.thing_code(x, y).zero?
  end
end
