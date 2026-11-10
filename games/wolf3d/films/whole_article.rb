# frozen_string_literal: true

# A WHOLE BUILD'S END ARTICLE, laid out into pages by the unpacking (EndArticleUnpacking): the
# screen that says you won, then the first episode's article, a page and the next. The copy is the
# one this machine names, so the film is made once for each:
#
#   rake film NAME=whole_article
#   WOLF3D_COPY=shareware rake film NAME=whole_article
require_relative "../lib/wolf3d"
require_relative "../test/support/article_scene"
require "stringio"

scene = Wolf3DTest::ArticleScene
program = Wolf3D::GAME.checked_program(err: StringIO.new, settings: scene::SETTINGS.merge(hold: "whole"))
VBlank::Diagnostics::Film.make(ARGV.fetch(0),
                               sides: { Wolf3D.data.label => -> { VBlank::Playthroughs::LoweredGame.new(program, "interpreter") } },
                               parts: [1..scene::FILM_FRAMES],
                               keys: ->(frame) { scene.keys(frame) })
