require "stringio"

module Circadex
  class Renderer
    # News sections flow one after another; stories share pages instead of each starting a new one.
    module News
      COLUMN_GAP = 16
      PARAGRAPH_INDENT = "    ".freeze

      private

      def news_pages(sections)
        visible = sections.select { |section| section_visible?(section) }
        visible.each_with_index { |section, index| news_section(section, first: index.zero?) }
      end

      # A section is skipped entirely when its only story was already printed in full on page one.
      def section_visible?(section)
        stories = section.stories.reject { |s| s.equal?(@lead) && @lead_leftover.to_s.empty? }
        !(stories.empty? && section.briefs.empty? && section.notice.to_s.empty?)
      end

      def news_section(section, first:)
        pdf.start_new_page if (first && @overflow_mail.empty?) || pdf.cursor < 230
        section_start(section.title, slug(section.title))
        section_band(section.title)
        put(section.notice, 0, pdf.cursor, pdf.bounds.width, size: 8.5, style: :italic, color: MUTED).then { |h| pdf.move_down(h + 4) if h.positive? }
        lead_continued if section.stories.any? { |s| s.equal?(@lead) } && !@lead_leftover.to_s.empty?
        section.stories.reject { |s| s.equal?(@lead) }.each_with_index { |story, index| story(story, lead: index.zero? && @lead.nil?) }
        briefs(section) unless section.briefs.empty?
        pdf.move_down 16
      end

      # The rest of the story that began on page one.
      def lead_continued
        room(120)
        pdf.add_dest("lead-continued", pdf.dest_fit)
        @pages["sec-lead"] = pdf.page_number
        pdf.move_down 6
        pdf.text clean("Continued from page 1: #{@lead.title}"), size: 9, style: :italic, color: MUTED
        pdf.move_down 4
        flow_columns(@lead_leftover)
        pdf.move_down 6
        rule 0.4, color: FAINT
      end

      def story(story, lead:)
        room(160)
        pdf.move_down 8
        size = lead ? 20 : 15.5
        pdf.text clean(story.title), size: size, style: :bold, leading: 1
        meta = [story.source, story.byline, story.published&.strftime("%-I:%M %p")].compact.join("  ·  ")
        pdf.text clean(meta), size: 7.8, style: :italic, color: MUTED
        pdf.move_down 4
        pdf.text clean(story.summary), size: @body_pt + 0.5, style: :italic unless story.summary.to_s.empty? || story.paragraphs == [story.summary]
        pdf.move_down 5
        story_image(story)
        flow_columns(story.paragraphs.map { |p| "#{PARAGRAPH_INDENT}#{clean(p)}" }.join("\n"))
        pdf.move_down 6
        rule 0.4, color: FAINT
      end

      def story_image(story)
        return unless story.image

        room(190)
        pdf.image StringIO.new(story.image), fit: [pdf.bounds.width, 125], position: :center
        pdf.move_down 6
      rescue Prawn::Errors::UnsupportedImageType
        nil
      end

      # Lays text out in two balanced columns, continuing onto new pages as needed.
      def flow_columns(text)
        column_width = (pdf.bounds.width - COLUMN_GAP) / 2.0
        options = { size: @body_pt, leading: 1.5, align: :justify }
        line = @body_pt * 1.2 + options[:leading]

        until text.empty?
          pdf.start_new_page if pdf.cursor < line * 4
          height = balanced_height(text, column_width, options, line)
          top = pdf.cursor
          left = column_text(text, [0, top], column_width, height, options)
          left = column_text(left, [column_width + COLUMN_GAP, top], column_width, height, options)
          pdf.stroke_color FAINT
          pdf.line_width 0.3
          pdf.stroke_line [column_width + COLUMN_GAP / 2.0, top], [column_width + COLUMN_GAP / 2.0, top - height]
          pdf.stroke_color INK
          pdf.move_down height
          text = left
          pdf.start_new_page unless text.empty?
        end
      end

      def balanced_height(text, width, options, line)
        available = pdf.cursor
        height = [pdf.height_of(text, options.merge(width: width)) / 2.0, line].max
        while height < available
          leftover = column_text(text, [0, pdf.cursor], width, height, options, dry_run: true)
          leftover = column_text(leftover, [0, pdf.cursor], width, height, options, dry_run: true)
          return height if leftover.empty?

          height += line
        end
        available
      end

      def column_text(text, at, width, height, options, dry_run: false)
        return "" if text.empty?

        Prawn::Text::Box.new(text, options.merge(document: pdf, at: at, width: width, height: height)).render(dry_run: dry_run).to_s
      end

      # "Also in ..." items, balanced into two columns by measured height.
      def briefs(section)
        room(110)
        pdf.move_down 10
        pdf.text clean("Also in #{section.title}"), size: 11, style: :bold
        rule 0.5
        pdf.move_down 5
        width = (pdf.bounds.width - COLUMN_GAP) / 2.0
        heights = section.briefs.map { |b| brief_height(b, width) }
        split = balance_split(heights)
        top = pdf.cursor
        used = [section.briefs.first(split), section.briefs.drop(split)].each_with_index.map do |items, i|
          y = top
          items.each { |brief| y -= draw_brief(brief, i * (width + COLUMN_GAP), y, width) }
          top - y
        end
        pdf.move_cursor_to(top - used.max)
      end

      def brief_height(brief, width)
        measure(brief.title, width, size: @body_pt, style: :bold) + measure(brief.summary, width, size: @body_pt - 1) + 11 + 6
      end

      def draw_brief(brief, x, y, width)
        used = put(brief.title, x, y, width, size: @body_pt, style: :bold)
        used += put(brief.summary, x, y - used, width, size: @body_pt - 1)
        used += put(brief.source, x, y - used, width, size: 7.3, style: :italic, color: MUTED)
        used + 6
      end

      def balance_split(heights)
        total = heights.sum
        running = 0
        heights.each_with_index do |h, i|
          running += h
          return i + 1 if running >= total / 2.0
        end
        heights.size
      end
    end
  end
end
