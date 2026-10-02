# frozen_string_literal: true

module Wolf3D
  # WHAT A SAVED GAME HOLDS: everything about a game in progress that lasts from one pass to the
  # next and is not worked out again from the rest. Where the player stands, what they carry, how
  # far open each door is, where every guard is and what he is doing.
  #
  # DECLARING A THING THROUGH THIS IS KEEPING IT. A part of the game writes
  # `@lasting.var :keys, 0` where it would write `b.var :keys, 0`, and the declaration stays where
  # it was, beside the comment that says what the thing is. So there is no second list of what a
  # save holds to fall out of step with the first: a thing cannot be declared lasting and left out
  # of the save.
  #
  # WHAT IS NOT IN IT is named with an underscore, and is one of two things. Working room, which
  # nothing reads from one pass to the next. Or a thing worked out from the rest, such as where
  # the floor being played has its slice of each table: a load puts the floor back, and
  # Playthrough's :resume works the slices out again from it. The few things that last and are
  # still not saved are in LEFT_OUT, each with its reason.
  #
  # THE FRAMEWORK HOLDS THE GAME TO THIS while the cartridge is built: a game that says
  # `saves_keep_everything except: LastingState::LEFT_OUT.keys` will not build while any variable,
  # list or pool without an underscore is neither kept nor left out on purpose.
  class LastingState
    # WHAT A SAVED GAME LEAVES OUT ON PURPOSE, though it lasts, and why. Each is the original's own
    # choice: SaveTheGame (wl_main.cpp) writes the game's state and the floor's, and none of these.
    # The names are what the framework's `saves_keep_everything` is told to leave out.
    LEFT_OUT = Ractor.make_shareable({
      sound_on: "A setting, not part of a game. The original keeps it in its config file " \
                "(WriteConfig, wl_main.cpp), so loading a game leaves it as the player set it.",
      screen: "Which menu is up. Loading is done from a menu and goes straight into the game.",
      noise: "A shot heard for the next pass or two. The original's madenoise is a global " \
             "outside gamestate, and a save never writes it.",
      random_numbers: "The original never writes rndindex, so a loaded game rolls on from " \
                      "wherever the numbers have got to, and the guard who was going to miss " \
                      "may hit."
    })

    def initialize(build:)
      @b = build
      @kept = []
      @names = []
      @record = nil
    end

    # The names of everything kept so far, in the order the record holds them.
    def names = @names.dup

    # A variable, declared and kept.
    def var(name, init) = kept(name) { @b.var(name, init) }

    # A list, declared and kept: every item, and how many there are.
    def list(name, **) = kept(name) { @b.list(name, **) }

    # A pool, declared and kept WHOLE: every field of every slot, and which slots are live. The
    # framework puts the pool back slot for slot, so the next one spawned lands where it would
    # have.
    def pool(name, **) = kept(name) { @b.pool(name, **) }

    # HAND EVERYTHING OVER to a save record (the framework's `save_data`), in one call: what has
    # been declared so far, and everything declared after.
    def keep_in(record)
      if @record
        raise ArgumentError, "The game already has one save record. One save record holds the " \
                             "whole game. To fix this, call keep_in once."
      end

      @record = record
      @kept.each { |thing| record.keep thing }
    end

    private

    # The thing +declaring+ declares as +name+, kept. The checks come before it is declared, so a
    # refused name never reaches the cartridge.
    def kept(name, &declaring)
      check_name!(name)
      @names << name
      thing = declaring.call
      @kept << thing
      @record&.keep thing
      thing
    end

    def check_name!(name)
      if name.start_with?("_")
        raise ArgumentError, "A saved game cannot keep :#{name}. A name that starts with an " \
                             "underscore is working room, and a save never holds it. To fix " \
                             "this, declare :#{name} with the builder, or name it without the " \
                             "underscore."
      end
      return unless @names.include?(name)

      raise ArgumentError, "The game declares :#{name} twice as lasting state. To fix this, " \
                           "give one of the two a different name."
    end
  end
end
