require "prawn"

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
