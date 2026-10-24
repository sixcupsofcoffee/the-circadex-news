require "prawn"

require_relative "renderer/typography"
require_relative "renderer/icons"
require_relative "renderer/charts"
require_relative "renderer/pages"
require_relative "renderer/traffic"
require_relative "renderer/front_page"
require_relative "renderer/news"
require_relative "renderer/puzzles"

module Circadex
  # Turns an Edition into a PDF. Layout is done in two passes so the contents list can
  # show the page each section actually landed on.
  class Renderer
    include Typography
    include Icons
    include Charts
    include Pages
    include Traffic
    include FrontPage
    include News
    include Puzzles

    def initialize(config)
      @page = config["page"]
      @paper = config["paper"] || { "name" => "The Circadex Chronicle" }
      @location = (config["weather"] || {})["location_name"]
      @analytics_show = Array((config["analytics"] || {})["show"] || Sources::Analytics::SHOW).map(&:to_s)
      @body_pt = @page["body_pt"].to_f
    end

    def render_file(edition, path)
      build(edition).render_file(path)
    end

    def build(edition)
      _, pages = layout(edition, {})
      layout(edition, pages).first
    end

    private

    attr_reader :pdf

    def layout(edition, known_pages)
      @known_pages = known_pages
      @pages = {}
      @outline = []
      @pdf = Prawn::Document.new(
        page_size: [@page["width_in"] * 72, @page["height_in"] * 72],
        margin: [@page["margin_pt"], @page["margin_pt"], @page["margin_pt"] + 10, @page["margin_pt"]],
        info: { Title: "#{@paper['name']}, #{edition.date.iso8601}", Creator: "the-circadex-news" }
      )
      register_fonts
      pdf.fill_color INK
      pdf.stroke_color INK

      front_page(edition)
      inbox_page
      news_pages(edition.sections)
      traffic_page(edition.analytics) if edition.analytics
      crossword_page(edition.crossword) if edition.crossword
      comics_page(edition.comics) if edition.comics
      notes_page(edition)

      page_numbers
      define_outline
      [pdf, @pages]
    end
  end
end
