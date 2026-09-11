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

gem "minitest", "~> 6.0"
gem "rake", "~> 13.0"
