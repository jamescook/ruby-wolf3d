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
gem "ruby-gba", github: "jamescook/ruby-gba", branch: "main"

# THE EMULATOR, which is a gem of its own and not a dependency of ruby-gba — building a
# cartridge is pure Ruby, and only running one needs a C compiler and libmgba. This suite runs
# the built cartridge on a real console, so it needs it.
#
# `glob:` is how bundler finds a gemspec that is not at the root of a repository; the emulator
# lives in a subdirectory of ruby-gba's. Bundler builds its C extension on install, per Ruby
# ABI — which is what makes changing Ruby version a rebuild rather than a library that will not
# load. It needs libmgba: brew install mgba, or apt install libmgba-dev.
gem "ruby-gba-emulator", github: "jamescook/ruby-gba", branch: "main",
                         glob: "ruby-gba-emulator/ruby-gba-emulator.gemspec"

gem "minitest", "~> 6.0"
gem "rake", "~> 13.0"
