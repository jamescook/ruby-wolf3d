# frozen_string_literal: true

module Wolf3D
  # WHAT HAPPENS NEXT, the few paragraphs each episode ends on (EndText, wl_text.cpp). They live in
  # VGAGRAPH as plain text with commands in it, each a caret and a letter:
  #
  #   ^P  a new page          ^E  the end
  #   ^C7e and ^c7e  a colour, in two hex digits
  #   ^G16,16,5  a picture at that place
  #
  # THE PICTURE AND THE COLOUR ARE LEFT OUT. There are 240 columns here where the original lays out
  # 320, and its picture sits in the margin the words are meant to wrap around, which a page this
  # narrow has no room for. So the words fill the width, and a page that overflows goes on to the next.
  module EndArticle
    COMMAND = /\^(?:[Cc]\h\h|G\d+,\d+,\d+)/
    PAGE_BREAK = "^P"
    FINISH = "^E"

    # THE PAGES OF +text+, each a list of lines, wrapped to +width+ pixels and +lines+ rows. A block
    # says how wide a character is.
    def self.pages(text, width:, lines:, &char_width)
      body = text.delete("\r").split(FINISH).first.to_s.gsub(COMMAND, "")
      body.split(PAGE_BREAK).map(&:strip).reject(&:empty?).flat_map do |page|
        wrapped = page.split("\n", -1).flat_map { |paragraph| wrap(paragraph, width, &char_width) }
        wrapped.each_slice(lines).to_a
      end
    end

    # A paragraph into lines, a word at a time.
    def self.wrap(paragraph, width, &char_width)
      return [""] if paragraph.strip.empty?

      words = paragraph.split
      lines = [words.shift]
      words.each do |word|
        wider = "#{lines.last} #{word}"
        if wider.each_char.sum(&char_width) > width
          lines << word
        else
          lines[-1] = wider
        end
      end
      lines
    end
  end
end
