require "prawn"
require "stringio"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Circadex
  class Renderer
    INK = "111111".freeze
    MUTED = "555555".freeze
    COLUMN_GAP = 16
    PARAGRAPH_INDENT = "\u00A0" * 4

    def initialize(config)
      @page = config["page"]
      @body_pt = @page["body_pt"].to_f
    end

    def render_file(edition, path)
      build(edition).render_file(path)
    end

    def build(edition)
      @outline = []
      pdf = Prawn::Document.new(
        page_size: [@page["width_in"] * 72, @page["height_in"] * 72],
        margin: [@page["margin_pt"], @page["margin_pt"], @page["margin_pt"] + 10, @page["margin_pt"]],
        info: { Title: "The Circadex, #{edition.date.iso8601}", Creator: "the-circadex-news" }
      )
      pdf.font "Times-Roman"
      pdf.fill_color INK

      masthead(pdf, edition)
      weather(pdf, edition.forecast) if edition.forecast
      mail(pdf, edition.mail) if edition.mail
      analytics(pdf, edition.analytics) if edition.analytics
      comics(pdf, edition.comics) if edition.comics
      crossword(pdf, edition.crossword) if edition.crossword
      edition.sections.each { |section| news_section(pdf, section) }
      notes(pdf, edition.notices) unless edition.notices.empty?

      page_numbers(pdf)
      define_outline(pdf)
      pdf
    end

    private

    def masthead(pdf, edition)
      pdf.font("Times-Bold") { pdf.text "THE CIRCADEX", size: 34, align: :center }
      rule(pdf, 2)
      pdf.move_down 2
      rule(pdf, 0.5)
      pdf.move_down 5
      pdf.text clean(dateline(edition)), size: 9, align: :center, style: :italic
      pdf.move_down 10
    end

    def dateline(edition)
      label = edition.date.sunday? ? "Sunday Edition" : "Daily Edition"
      "#{edition.date.strftime('%A, %B %-d, %Y')}  •  #{label}"
    end

    def weather(pdf, forecast)
      mark(pdf, "Weather")
      section_header(pdf, "Weather")
      today = forecast.today
      pdf.font("Times-Bold") { pdf.text clean("#{forecast.location}: #{today.summary}"), size: 13 }
      pdf.text clean("High #{today.high}°  •  Low #{today.low}°#{precip(today)}"), size: @body_pt + 1
      pdf.move_down 8
      pdf.font("Times-Bold") { pdf.text "The next five days", size: @body_pt + 1 }
      pdf.move_down 2
      forecast.upcoming.each do |day|
        line = "#{day.date.strftime('%a %-d')}   #{day.high}° / #{day.low}°   #{day.summary}#{precip(day)}"
        pdf.text clean(line), size: @body_pt
      end
    end

    def precip(day)
      day.precip && day.precip >= 20 ? "  •  #{day.precip}% chance of precipitation" : ""
    end

    def mail(pdf, digest)
      pdf.start_new_page
      mark(pdf, "Mail")
      section_header(pdf, "Mail since midnight")
      pdf.text clean(mail_summary(digest)), size: 9, style: :italic, color: MUTED
      mail_group(pdf, "Needs attention", digest.attention, snippets: true)
      mail_group(pdf, "Messages", digest.messages, snippets: true)
      mail_group(pdf, "Newsletters", digest.newsletters, snippets: true)
    end

    def mail_summary(digest)
      parts = ["#{digest.total} #{digest.total == 1 ? 'message' : 'messages'}"]
      parts << "#{digest.skipped} promotional skipped" if digest.skipped.positive?
      parts << "showing the newest only" if digest.truncated
      parts.join("  \u2022  ")
    end

    def mail_group(pdf, title, messages, snippets:)
      return if messages.empty?

      room(pdf, 80)
      pdf.move_down 10
      pdf.font("Times-Bold") { pdf.text clean(title), size: 12 }
      rule(pdf, 0.5)
      pdf.move_down 4
      messages.each { |message| mail_entry(pdf, message, snippets: snippets) }
    end

    def mail_entry(pdf, message, snippets:)
      room(pdf, 60)
      pdf.font("Times-Bold") { pdf.text clean(message.subject), size: @body_pt + 0.5 }
      pdf.text clean("#{message.from}  \u2022  #{message.received.strftime('%-I:%M %p')}"), size: 8.5, style: :italic, color: MUTED
      pdf.text clean(message.snippet), size: @body_pt - 0.5 if snippets && !message.snippet.to_s.empty?
      pdf.move_down 6
    end

    def room(pdf, points)
      pdf.start_new_page if pdf.cursor < points
    end

    def analytics(pdf, digest)
      pdf.start_new_page
      mark(pdf, "Site traffic")
      section_header(pdf, "Site traffic")
      pdf.text clean("#{digest.date.strftime('%A, %B %-d')}  \u2022  counts are Cloudflare estimates"), size: 9, style: :italic, color: MUTED
      digest.sites.each { |site| analytics_site(pdf, site) }
    end

    def analytics_site(pdf, site)
      room(pdf, 140)
      pdf.move_down 12
      pdf.font("Times-Bold") { pdf.text clean(site.name), size: 14 }
      rule(pdf, 0.5)
      pdf.move_down 4
      return pdf.text(clean(site.notice), size: @body_pt, style: :italic) unless site.views

      pdf.text clean("#{count(site.views)} page views  \u2022  #{count(site.visits)} visits"), size: @body_pt + 2
      pdf.text clean(traffic_comparison(site)), size: 9, style: :italic, color: MUTED
      analytics_list(pdf, "Top pages", site.pages)
      analytics_list(pdf, "Referrers", site.referrers)
      pdf.text clean(site.notice), size: 8.5, style: :italic, color: MUTED if site.notice
    end

    def traffic_comparison(site)
      parts = [["the day before", site.prior_views], ["the 7-day average", site.average_views]].map do |label, base|
        delta = Sources::Analytics.change(site.views, base)
        delta ? "#{delta.positive? ? '+' : ''}#{delta}% vs #{label}" : nil
      end
      parts.compact.join("  \u2022  ")
    end

    def analytics_list(pdf, title, rows)
      return if rows.empty?

      pdf.move_down 5
      pdf.font("Times-Bold") { pdf.text clean(title), size: @body_pt }
      rows.each { |label, n| pdf.text clean("#{Text.truncate(label, 60)}   #{count(n)}"), size: @body_pt - 0.5 }
    end

    def count(number)
      number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    end

    CELL_SIZES = [30, 28, 26, 24, 22, 20, 18].freeze
    CLUE_SIZES = [9.5, 9, 8.5, 8].freeze

    def crossword(pdf, puzzle)
      pdf.start_new_page
      mark(pdf, "Crossword")
      section_header(pdf, "Crossword")
      pdf.font("Times-Bold") { pdf.text clean(puzzle.title), size: 11 }
      credit = ["The Guardian", puzzle.setter && "set by #{puzzle.setter}"].compact.join("  \u2022  ")
      pdf.text clean(credit), size: 8.5, style: :italic, color: MUTED
      pdf.move_down 8

      column_width = (pdf.bounds.width - COLUMN_GAP) / 2.0
      cell, size = crossword_fit(pdf, puzzle, column_width)
      crossword_grid(pdf, puzzle, cell)
      pdf.move_down 10
      crossword_clues(pdf, puzzle, column_width, size)
    end

    def crossword_fit(pdf, puzzle, column_width)
      cell_limit = (pdf.bounds.width / puzzle.cols).floor
      CELL_SIZES.each do |cell|
        next if cell > cell_limit

        CLUE_SIZES.each do |size|
          return [cell, size] if puzzle.rows * cell + 10 + clue_height(pdf, puzzle, column_width, size) <= pdf.cursor
        end
      end
      [[CELL_SIZES.last, cell_limit].min, CLUE_SIZES.last]
    end

    def clue_height(pdf, puzzle, width, size)
      [puzzle.across, puzzle.down].map do |clues|
        heading = size + 8
        heading + clues.sum { |number, text| pdf.height_of(clue_markup(number, text), width: width, size: size, inline_format: true) + 2 }
      end.max
    end

    def crossword_grid(pdf, puzzle, cell)
      left = (pdf.bounds.width - puzzle.cols * cell) / 2.0
      top = pdf.cursor
      pdf.line_width 0.8
      puzzle.rows.times do |row|
        puzzle.cols.times do |col|
          x = left + col * cell
          y = top - row * cell
          if puzzle.cells.key?([col, row])
            pdf.stroke_rectangle [x, y], cell, cell
            number = puzzle.cells[[col, row]]
            pdf.text_box number.to_s, at: [x + 2, y - 1.5], width: cell - 2, height: 8, size: 6.5 if number
          else
            pdf.fill_rectangle [x, y], cell, cell
          end
        end
      end
      pdf.fill_color INK
      pdf.move_down puzzle.rows * cell
    end

    def crossword_clues(pdf, puzzle, column_width, size)
      top = pdf.cursor
      [["Across", puzzle.across, 0], ["Down", puzzle.down, column_width + COLUMN_GAP]].each do |title, clues, x|
        pdf.bounding_box([x, top], width: column_width) do
          pdf.font("Times-Bold") { pdf.text title, size: size + 2 }
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

    def comics(pdf, digest)
      pdf.start_new_page
      mark(pdf, "Comics")
      section_header(pdf, "Comics")
      digest.strips.each { |strip| comic(pdf, strip) }
    end

    def comic(pdf, strip)
      room(pdf, 200)
      pdf.move_down 10
      pdf.font("Times-Bold") { pdf.text clean(strip.name), size: 11 }
      pdf.move_down 3
      return pdf.text(clean(strip.notice || "Unavailable today."), size: @body_pt, style: :italic, color: MUTED) unless strip.image

      pdf.image StringIO.new(strip.image), fit: [pdf.bounds.width, [pdf.cursor - 10, 340].min]
      pdf.move_down 6
    rescue Prawn::Errors::UnsupportedImageType
      pdf.text clean("#{strip.name} could not be displayed today."), size: @body_pt, style: :italic, color: MUTED
    end

    def news_section(pdf, section)
      pdf.start_new_page
      mark(pdf, section.title)
      section_header(pdf, section.title)
      pdf.text clean(section.notice), size: 9, style: :italic, color: MUTED if section.notice
      section.stories.each { |story| story(pdf, story) }
      briefs(pdf, section) unless section.briefs.empty?
    end

    def story(pdf, story)
      pdf.start_new_page if pdf.cursor < 140
      pdf.move_down 12
      pdf.font("Times-Bold") { pdf.text clean(story.title), size: 17, leading: 1 }
      pdf.text clean(story_meta(story)), size: 8.5, style: :italic, color: MUTED
      pdf.move_down 5
      pdf.text clean(story.summary), size: @body_pt + 0.5, style: :italic unless story.summary.to_s.empty? || story.paragraphs == [story.summary]
      pdf.move_down 5
      flow_columns(pdf, story.paragraphs.map { |p| "#{PARAGRAPH_INDENT}#{clean(p)}" }.join("\n"))
    end

    # Lays text out in two balanced columns, continuing onto new pages as needed.
    # Prawn's column_box fills the first column to the page bottom, so we size the
    # columns ourselves.
    def flow_columns(pdf, text)
      column_width = (pdf.bounds.width - COLUMN_GAP) / 2.0
      options = { size: @body_pt, leading: 1.5, align: :justify }
      line = @body_pt * 1.2 + options[:leading]

      until text.empty?
        pdf.start_new_page if pdf.cursor < line * 4
        height = balanced_height(pdf, text, column_width, options, line)
        top = pdf.cursor
        left = column(pdf, text, [0, top], column_width, height, options)
        left = column(pdf, left, [column_width + COLUMN_GAP, top], column_width, height, options)
        pdf.move_down height
        text = left
        pdf.start_new_page unless text.empty?
      end
    end

    def balanced_height(pdf, text, width, options, line)
      available = pdf.cursor
      estimate = pdf.height_of(text, options.merge(width: width))
      height = [estimate / 2.0, line].max
      while height < available
        leftover = column(pdf, text, [0, pdf.cursor], width, height, options, dry_run: true)
        leftover = column(pdf, leftover, [0, pdf.cursor], width, height, options, dry_run: true)
        return height if leftover.empty?

        height += line
      end
      available
    end

    def column(pdf, text, at, width, height, options, dry_run: false)
      return "" if text.empty?

      box = Prawn::Text::Box.new(text, options.merge(document: pdf, at: at, width: width, height: height))
      box.render(dry_run: dry_run).to_s
    end

    def story_meta(story)
      [story.source, story.byline, story.published&.strftime("%-I:%M %p")].compact.join("  •  ")
    end

    def briefs(pdf, section)
      pdf.start_new_page if pdf.cursor < 120
      pdf.move_down 14
      pdf.font("Times-Bold") { pdf.text clean("Also in #{section.title}"), size: 12 }
      rule(pdf, 0.5)
      pdf.move_down 4
      section.briefs.each do |brief|
        pdf.font("Times-Bold") { pdf.text clean(brief.title), size: @body_pt + 0.5 }
        pdf.text clean(brief.summary), size: @body_pt - 0.5 unless brief.summary.to_s.empty?
        pdf.text clean(brief.source), size: 8, style: :italic, color: MUTED
        pdf.move_down 5
      end
    end

    def notes(pdf, notices)
      pdf.start_new_page
      mark(pdf, "Notes")
      section_header(pdf, "Notes")
      notices.each { |notice| pdf.text clean(notice), size: @body_pt }
    end

    def section_header(pdf, title)
      pdf.font("Times-Bold") { pdf.text clean(title.upcase), size: 15 }
      rule(pdf, 1)
      pdf.move_down 4
    end

    def rule(pdf, width)
      pdf.line_width width
      pdf.stroke_horizontal_rule
    end

    def mark(pdf, name)
      @outline << [name, pdf.page_number]
    end

    def page_numbers(pdf)
      pdf.number_pages "<page> / <total>", at: [pdf.bounds.left, -14], width: pdf.bounds.width, align: :center, size: 8
    end

    def define_outline(pdf)
      entries = @outline
      pdf.outline.define do
        entries.each { |name, page| section(name, destination: page) }
      end
    end

    def clean(str)
      Text.clean(str)
    end
  end
end
