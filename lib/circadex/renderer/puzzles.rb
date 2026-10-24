require "stringio"

module Circadex
  class Renderer
    # The crossword and the comics.
    module Puzzles
      CELL_SIZES = [30, 28, 26, 24, 22, 20, 18].freeze
      CLUE_SIZES = [9.5, 9, 8.5, 8].freeze
      PUZZLE_GAP = 16

      private

      # --- crossword --------------------------------------------------------------------------

      def crossword_page(puzzle)
        pdf.start_new_page
        section_start("Crossword", "crossword")
        section_band("Crossword")
        pdf.text clean(puzzle.title), size: 11, style: :bold
        credit = ["The Guardian", puzzle.setter && "set by #{puzzle.setter}"].compact.join("  ·  ")
        pdf.text clean(credit), size: 8, style: :italic, color: MUTED
        pdf.move_down 8

        column_width = (pdf.bounds.width - PUZZLE_GAP) / 2.0
        cell, size = crossword_fit(puzzle, column_width)
        crossword_grid(puzzle, cell)
        pdf.move_down 10
        crossword_clues(puzzle, column_width, size)
      end

      def crossword_fit(puzzle, column_width)
        cell_limit = (pdf.bounds.width / puzzle.cols).floor
        CELL_SIZES.each do |cell|
          next if cell > cell_limit

          CLUE_SIZES.each do |size|
            return [cell, size] if puzzle.rows * cell + 10 + clue_height(puzzle, column_width, size) <= pdf.cursor
          end
        end
        [[CELL_SIZES.last, cell_limit].min, CLUE_SIZES.last]
      end

      def clue_height(puzzle, width, size)
        [puzzle.across, puzzle.down].map do |clues|
          size + 8 + clues.sum { |number, text| pdf.height_of(clue_markup(number, text), width: width, size: size, inline_format: true) + 2 }
        end.max
      end

      def crossword_grid(puzzle, cell)
        left = (pdf.bounds.width - puzzle.cols * cell) / 2.0
        top = pdf.cursor
        pdf.line_width 0.8
        pdf.stroke_color INK
        puzzle.rows.times do |row|
          puzzle.cols.times do |col|
            x = left + col * cell
            y = top - row * cell
            if puzzle.cells.key?([col, row])
              pdf.stroke_rectangle [x, y], cell, cell
              number = puzzle.cells[[col, row]]
              put(number.to_s, x + 2, y - 1.5, cell - 2, size: 6.5, font: SANS) if number
            else
              pdf.fill_color INK
              pdf.fill_rectangle [x, y], cell, cell
            end
          end
        end
        pdf.fill_color INK
        pdf.move_down puzzle.rows * cell
      end

      def crossword_clues(puzzle, column_width, size)
        top = pdf.cursor
        [["Across", puzzle.across, 0], ["Down", puzzle.down, column_width + PUZZLE_GAP]].each do |title, clues, x|
          pdf.bounding_box([x, top], width: column_width) do
            pdf.text title, size: size + 2, style: :bold
            pdf.move_down 2
            clues.each do |number, text|
              pdf.text clue_markup(number, text), size: size, inline_format: true
              pdf.move_down 2
            end
          end
        end
      end

      def clue_markup(number, text)
        "<b>#{inline_escape(number)}</b> #{inline_escape(text)}"
      end

      def inline_escape(str)
        clean(str).gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      # --- comics -----------------------------------------------------------------------------

      def comics_page(digest)
        pdf.start_new_page
        section_start("Comics", "comics")
        section_band("Comics")
        digest.strips.each { |strip| comic(strip) }
      end

      def comic(strip)
        room(200)
        pdf.move_down 8
        pdf.text clean(strip.name), size: 10, style: :bold
        pdf.move_down 3
        return pdf.text(clean(strip.notice || "Unavailable today."), size: @body_pt, style: :italic, color: MUTED) unless strip.image

        pdf.image StringIO.new(strip.image), fit: [pdf.bounds.width, [pdf.cursor - 10, 340].min]
        pdf.move_down 6
      rescue Prawn::Errors::UnsupportedImageType
        pdf.text clean("#{strip.name} could not be displayed today."), size: @body_pt, style: :italic, color: MUTED
      end
    end
  end
end
