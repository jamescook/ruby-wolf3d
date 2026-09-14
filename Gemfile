# frozen_string_literal: true

source "https://rubygems.org"

# The framework this game is built with. From git rather than rubygems because ruby-gba is
# pre-1.0 and this game is its largest consumer — the two still move together, and a released
# version for every experiment would be a lie about how settled the API is. Unpinned on
# purpose: a break here is worth knowing about the day it lands, which is the whole reason
# this game exists.
#
# WORKING ON BOTH AT ONCE: point bundler at a checkout beside this one and it resolves
# against that instead of fetching, with no edit to this file —
#
#   bundle config --local local.ruby-gba ../ruby-gba
#
# which is why `branch:` is named: bundler only accepts a local override for a branch it can
# check you are on. Undo it with `bundle config --delete local.ruby-gba`.
# ONE BLOCK FOR BOTH GEMS, because both live in that one repository.
#
# The obvious way to write this is two `gem` lines each naming the same github: — and it is
# wrong. Bundler counts `glob:` as part of a git source's identity, so two lines with different
# globs are TWO sources; but the directory it clones into is named from the URL alone. Two
# sources, one directory, and on a cold cache they race and the clone dies:
#
#   fatal: cannot copy '.../templates/info/exclude' to '.../info/exclude': File exists
#   fatal: shallow file has changed since we read it
#
# A `git ... do ... end` block is one source holding both gems: one clone, one revision, and
# they can never end up on different commits of the same repository. The glob has to match both
# gemspecs — the framework's at the root, the emulator's a directory down.
#
# THE EMULATOR is a gem of its own and not a dependency of ruby-gba: building a cartridge is
# pure Ruby, and only running one needs a C compiler and libmgba. This suite runs the built
# cartridge on a real console, so it needs it. Bundler builds its C extension on install, per
# Ruby ABI — which is what makes changing Ruby version a rebuild rather than a library that
# will not load. It needs libmgba: brew install mgba, or apt install libmgba-dev.
git "https://github.com/jamescook/ruby-gba.git",
    branch: "main",
    glob: "{,ruby-gba-emulator/}*.gemspec" do
  gem "ruby-gba"
  gem "ruby-gba-emulator"
end

gem "minitest", "~> 6.0"
gem "rake", "~> 13.0"

# For `rake build:profile` alone, which samples a build of this game. It is this game's own
# tool and not the framework's: what it measures is the time between typing the command and
# holding a cartridge, which is Ruby running on your machine. How the finished cartridge spends
# its frames is a different question with a different instrument (rom.profile).
gem "stackprof", "~> 0.2"
