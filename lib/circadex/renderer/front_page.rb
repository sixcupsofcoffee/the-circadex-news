module Circadex
  class Renderer
    # Page one: masthead, weather, mail and traffic, and the table of contents.
    module FrontPage
      TOC_HEIGHT = 76
      MAIL_HEAD = 15

      private

      def front_page(edition)
        masthead(edition)
        weather_strip(edition.forecast)
        pdf.move_down 10

        top = pdf.cursor
        height = top - TOC_HEIGHT - 8
        @overflow_mail = []
        @lead = choose_lead(edition.sections)
        @lead_leftover = ""
        columns(edition, top, height)
        pdf.move_cursor_to(top - height)
        contents(edition)
      end

      # The lead story: the first one with a picture, else the first story of the first section.
      def choose_lead(sections)
        sections.flat_map(&:stories).find(&:image) || sections.find { |s| s.stories.any? }&.stories&.first
      end

      def masthead(edition)
        name = clean(@paper["name"])
        font, style, size = @custom_masthead ? [MASTHEAD, :normal, 46.0] : [SERIF, :bold, 36.0]
        size -= 1 while size > 16 && text_width(name, size: size, style: style, font: font) > pdf.bounds.width - 12
        pdf.font(font, style: style) { pdf.text name, size: size, align: :center }
        pdf.move_down 3
        rule 2.2
        pdf.move_down 2
        rule 0.5
        pdf.move_down 4
        ear_line(edition)
        pdf.move_down 13
        rule 0.5
        pdf.move_down 8
      end

      def ear_line(edition)
        label = edition.date.sunday? ? "Sunday Edition" : "Daily Edition"
        third = pdf.bounds.width / 3
        y = pdf.cursor
        letterspaced(0.5) do
          put(@location.to_s.upcase, 0, y, third, size: 6.8, font: SANS, color: MUTED)
          put(edition.date.strftime("%A, %B %-d, %Y").upcase, third, y, third, size: 6.8, font: SANS, style: :bold, align: :center)
          put(label.upcase, third * 2, y, third, size: 6.8, font: SANS, color: MUTED, align: :right)
        end
      end

      # --- weather ---------------------------------------------------------------------------

      # One strip: today first, then the next five days.
      def weather_strip(forecast)
        unless forecast
          put("Weather unavailable today.", 0, pdf.cursor, pdf.bounds.width, size: 9, style: :italic, color: MUTED)
          return pdf.move_down(14)
        end

        days = [forecast.today] + forecast.upcoming.first(5)
        top = pdf.cursor
        cell = pdf.bounds.width / days.size
        days.each_with_index do |day, i|
          x = i * cell
          pdf.stroke_color FAINT
          pdf.line_width 0.4
          pdf.stroke_line [x, top - 3], [x, top - 66] unless i.zero?
          label = i.zero? ? "TODAY" : day.date.strftime("%a %-d").upcase
          letterspaced(0.4) { put(label, x, top - 3, cell, size: 7, font: SANS, style: :bold, align: :center) }
          weather_icon(day.code, x + cell / 2 - 14, top - 14, 28)
          put("#{day.high}\u00B0 / #{day.low}\u00B0", x, top - 46, cell, size: i.zero? ? 10.5 : 9.5, style: :bold, align: :center)
          detail = day.precip && day.precip >= 20 ? "#{day.summary}, #{day.precip}%" : day.summary
          put(fit_line(detail, cell - 6, size: 6.8, font: SANS), x, top - 57, cell, size: 6.8, font: SANS, color: MUTED, align: :center)
        end
        pdf.move_cursor_to(top - 68)
        rule 0.5, color: FAINT
        pdf.stroke_color INK
      end

      # --- mail and traffic ------------------------------------------------------------------

      def columns(edition, top, height)
        mail = edition.mail
        width = pdf.bounds.width
        gap = 18.0

        if mail
          left = (width - gap) * 0.62
          lead_story(0, top, left, height)
          pdf.stroke_color FAINT
          pdf.line_width 0.4
          pdf.stroke_line [left + gap / 2, top], [left + gap / 2, top - height + 6]
          @overflow_mail = mail_front(mail, left + gap, top, width - left - gap, height)
        else
          lead_story(0, top, width, height)
        end
        pdf.stroke_color INK
      end

      # The lead story's picture, headline and as much text as fits; the rest continues in its section.
      def lead_story(x, top, width, height)
        story = @lead
        return unless story

        y = top
        if story.image
          shown = lead_image(story, x, y, width, [height * 0.38, 170].min)
          y -= shown + 7
        end
        y -= put(story.title, x, y, width, size: width > 300 ? 20 : 17, style: :bold, leading: 1)
        meta = [story.source, story.byline, story.published&.strftime("%-I:%M %p")].compact.join("  \u00B7  ")
        y -= put(meta, x, y - 3, width, size: 7.4, style: :italic, color: MUTED) + 7
        y -= put(story.summary, x, y, width, size: @body_pt, style: :italic) + 6 unless story.summary.to_s.empty? || story.paragraphs == [story.summary]

        text = story.paragraphs.map { |p| "#{News::PARAGRAPH_INDENT}#{clean(p)}" }.join("\n")
        columns_needed = width > 380 ? 2 : 1
        gap = 14.0
        column_width = (width - gap * (columns_needed - 1)) / columns_needed
        area = y - (top - height) - 14
        options = { size: @body_pt - 0.5, leading: 1.4, align: :justify }
        columns_needed.times do |i|
          text = column_text(text, [x + i * (column_width + gap), y], column_width, area, options)
        end
        @lead_leftover = text
        return if text.empty?

        page = @known_pages["sec-lead"]
        put("Continued#{page ? " on page #{page}" : ''}", x, top - height + 10, width, size: 7.6, font: SANS, style: :bold, color: MUTED, align: :right)
      end

      # Draws the story picture centred in the given box; returns the height it used.
      def lead_image(story, x, top, width, max_height)
        info = pdf.image(StringIO.new(story.image), at: [x, top], fit: [width, max_height])
        info.scaled_height
      rescue Prawn::Errors::UnsupportedImageType
        0
      end

      def mail_front(digest, x, top, width, height)
        included = digest.attention.size + digest.messages.size + digest.newsletters.size
        letterspaced(0.6) { put("Mail since midnight  ·  #{included}".upcase, x, top, width, size: 6.8, font: SANS, style: :bold, color: MUTED) }
        pdf.stroke_color INK
        pdf.line_width 0.8
        pdf.stroke_line [x, top - 10], [x + width, top - 10]

        entries = digest.attention.map { |m| [:attention, m] } + digest.messages.map { |m| [:message, m] } + digest.newsletters.map { |m| [:newsletter, m] }
        if entries.empty?
          put("No mail since midnight.", x, top - 18, width, size: 9, style: :italic, color: MUTED)
          return []
        end

        y = top - MAIL_HEAD - 3
        floor = top - height + 18
        shown_group = nil
        entries.each_with_index do |(group, message), index|
          need = mail_entry_height(group, message, width) + (shown_group == group ? 0 : 13)
          limit = index == entries.size - 1 ? floor - 14 : floor
          if y - need < limit
            return mail_overflow(digest, entries.drop(index).map(&:last), x, floor, width)
          end

          if shown_group != group
            put(mail_group_label(group), x, y, width, size: 6.5, font: SANS, style: :bold, color: MUTED)
            y -= 11
            shown_group = group
          end
          y -= mail_entry(group, message, x, y, width)
        end
        []
      end

      def mail_group_label(group)
        { attention: "NEEDS ATTENTION", message: "MESSAGES", newsletter: "NEWSLETTERS" }.fetch(group)
      end

      def mail_entry_height(group, message, width)
        return 11.5 if group == :newsletter

        measure(message.subject, width - 8, size: 8.8, style: :bold) + 9.5 + 5
      end

      def mail_entry(group, message, x, y, width)
        sender = fit_line(message.from, width * 0.6, size: 7, font: SANS)
        if group == :newsletter
          line = fit_line("#{message.from}: #{message.subject}", width, size: 7.4)
          put(line, x, y, width, size: 7.4, color: MUTED)
          return 11.5
        end

        pdf.fill_color INK
        pdf.fill_rectangle [x, y - 2.5], 3.2, 3.2 if group == :attention
        used = put(message.subject, x + 8, y, width - 8, size: 8.8, style: :bold)
        put("#{sender}  ·  #{message.received.strftime('%-I:%M %p')}", x + 8, y - used - 0.5, width - 8, size: 7, font: SANS, color: MUTED)
        used + 9.5 + 5
      end

      def mail_overflow(_digest, leftover, x, floor, width)
        page = @known_pages["sec-inbox"]
        note = "+ #{leftover.size} more#{page ? " on page #{page}" : ''}"
        put(note, x, floor - 4, width, size: 7.2, font: SANS, style: :bold, color: MUTED)
        leftover
      end

      # --- continuation page for mail that did not fit on page one ----------------------------------

      def inbox_page
        return if @overflow_mail.empty?

        pdf.start_new_page
        section_start("Mail", "inbox")
        section_band("Mail")
        mail_continued
      end

      def mail_continued
        { "Needs attention" => %i[priority alert], "Messages" => %i[personal], "Newsletters" => %i[newsletter] }.each do |title, categories|
          items = @overflow_mail.select { |m| categories.include?(m.category) }
          next if items.empty?

          room(70)
          pdf.move_down 8
          pdf.text title, size: 11, style: :bold
          rule 0.5
          pdf.move_down 4
          items.each do |message|
            room(54)
            pdf.text clean(message.subject), size: 9.8, style: :bold
            pdf.text clean("#{message.from}  ·  #{message.received.strftime('%-I:%M %p')}"), size: 7.8, style: :italic, color: MUTED
            pdf.text clean(message.snippet), size: 8.8 unless message.snippet.to_s.empty?
            pdf.move_down 6
          end
        end
      end

      # --- table of contents -------------------------------------------------------------------

      def contents(edition)
        entries = toc_entries(edition)
        return if entries.empty? && !edition.mail

        rule 0.8, at: TOC_HEIGHT - 2
        letterspaced(0.6) { put("IN THIS EDITION", 0, TOC_HEIGHT - 8, 200, size: 6.8, font: SANS, style: :bold, color: MUTED) }
        per_column = 4
        list_columns = [(entries.size / per_column.to_f).ceil, 2].max
        total_columns = list_columns + (edition.mail ? 1 : 0)
        column_width = pdf.bounds.width / total_columns
        entries.each_with_index do |(title, dest), i|
          x = (i / per_column) * column_width
          y = TOC_HEIGHT - 22 - (i % per_column) * 12.5
          page = @known_pages[dest]
          put(title, x, y, column_width - 34, size: 9.2, style: :bold)
          leader(x + text_width(title, size: 9.2, style: :bold) + 4, x + column_width - 34, y - 8.5)
          put(page.to_s, x + column_width - 30, y, 24, size: 9.2, align: :right, color: MUTED)
          link(x, y, column_width - 8, 11, dest)
        end
        mail_count(edition.mail, list_columns * column_width, column_width) if edition.mail
      end

      # How much mail is in the paper, in the contents' last column.
      def mail_count(digest, x, width)
        included = digest.attention.size + digest.messages.size + digest.newsletters.size
        pdf.stroke_color FAINT
        pdf.line_width 0.4
        pdf.stroke_line [x - 6, TOC_HEIGHT - 12], [x - 6, 4]
        pdf.stroke_color INK
        letterspaced(0.6) { put("MAIL SINCE MIDNIGHT", x, TOC_HEIGHT - 8, width, size: 6.8, font: SANS, style: :bold, color: MUTED) }
        put(included.to_s, x, TOC_HEIGHT - 20, 50, size: 24, style: :bold)
        label = included == 1 ? "new message" : "new messages"
        put(label, x + text_width(included.to_s, size: 24, style: :bold) + 5, TOC_HEIGHT - 31, width, size: 8.5, font: SANS, color: MUTED)
        lines = []
        lines << "#{digest.attention.size} need attention" if digest.attention.any?
        lines << "#{digest.skipped} promotional skipped" if digest.skipped.positive?
        put(lines.join(" \u00B7 "), x, TOC_HEIGHT - 52, width, size: 7.2, font: SANS, color: MUTED)
      end

      def leader(from, to, y)
        return if to - from < 8

        pdf.stroke_color FAINT
        pdf.line_width 0.6
        pdf.dash(0.6, space: 2.4)
        pdf.stroke_line [from, y], [to, y]
        pdf.undash
        pdf.stroke_color INK
      end

      def toc_entries(edition)
        entries = edition.sections.select { |s| section_visible?(s) }.map { |s| [s.title, "sec-#{slug(s.title)}"] }
        entries << ["Mail", "sec-inbox"] unless @overflow_mail.empty?
        entries << ["Site Traffic", "sec-traffic"] if edition.analytics && !edition.analytics.sites.empty?
        entries << ["Crossword", "sec-crossword"] if edition.crossword
        entries << ["Comics", "sec-comics"] if edition.comics
        entries << ["Notes", "sec-notes"] unless edition.notices.empty?
        entries
      end
    end
  end
end
