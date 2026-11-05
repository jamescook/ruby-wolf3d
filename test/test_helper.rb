# frozen_string_literal: true

# The tests of the repository's own lib/, which knows nothing about Wolfenstein, so neither does
# this: no copy of the game and no framework. The game's tests have a setup of their own, in
# games/wolf3d/test/.
require "minitest/autorun"
require "minitest/ractor"
require_relative "../lib/id_software"

# Every test here runs in the pool of Ractors the game's suite runs in, so each class takes a
# share of the cores, and a constant it holds must be frozen all the way down.
module IdSoftwareTest
  def self.included(test_class)
    super
    test_class.parallelize_me!
  end
end
