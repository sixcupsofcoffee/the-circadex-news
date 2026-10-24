module Circadex
  class Renderer
    # Helpers every page type uses: section anchors, bands, links, page numbers.
    module Pages
      private

      def room(points)
        pdf.start_new_page if pdf.cursor < points
      end

      def slug(title)
        title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      end

      # Records where a section starts, for the contents list, links and PDF bookmarks.
      def section_start(title, key)
        dest = "sec-#{key}"
        pdf.add_dest(dest, pdf.dest_fit)
        @pages[dest] = pdf.page_number
        @outline << [title, pdf.page_number]
      end

      # A black band with the section name in spaced capitals.
      def section_band(title)
        top = pdf.cursor
        pdf.fill_color "000000"
        pdf.fill_rectangle [0, top], pdf.bounds.width, 15
        letterspaced(1.2) { put(title.upcase, 6, top - 3.5, pdf.bounds.width - 12, size: 8.4, font: SANS, style: :bold, color: "FFFFFF") }
        pdf.fill_color INK
        pdf.move_down 20
      end

      # A clickable area (x, y is its top-left corner within the current bounds).
      def link(x, y, width, height, dest)
        left = pdf.bounds.absolute_left + x
        bottom = pdf.bounds.absolute_bottom + y - height
        pdf.link_annotation([left, bottom, left + width, bottom + height], Dest: dest, Border: [0, 0, 0])
      end

      def notes_page(edition)
        return if edition.notices.empty?

        pdf.start_new_page
        section_start("Notes", "notes")
        section_band("Notes")
        edition.notices.each { |notice| pdf.text clean(notice), size: @body_pt }
      end

      def page_numbers
        pdf.font(SANS) do
          pdf.number_pages "<page> / <total>", at: [0, -14], width: pdf.bounds.width, align: :center, size: 7, color: MUTED
        end
      end

      def define_outline
        entries = @outline
        pdf.outline.define do
          entries.each { |name, page| section(name, destination: page) }
        end
      end
    end
  end
end
