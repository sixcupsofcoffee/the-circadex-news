require "nokogiri"

module Circadex
  module Sources
    # The Guardian publishes each puzzle's grid and clues as JSON inside the puzzle page.
    class GuardianCrossword
      class Error < StandardError; end

      PUZZLE_URL = "https://www.theguardian.com/crosswords/quick/%d".freeze
      INDEXES = [
        "https://www.theguardian.com/crosswords/series/quick/rss",
        "https://www.theguardian.com/crosswords/series/quick"
      ].freeze
      ID_PATTERN = %r{/crosswords/quick/(\d+)}
      ENUMERATION = /\(\d[\d,.\-\s]*\)\s*\z/

      def initialize(config, http: Http)
        @config = config
        @http = http
      end

      def fetch
        number = @config["number"] || latest_number
        parse(extract(@http.get(format(PUZZLE_URL, number.to_i))))
      end

      def latest_number
        INDEXES.each do |url|
          ids = @http.get(url).scan(ID_PATTERN).flatten.map(&:to_i)
          return ids.max unless ids.empty?
        rescue Http::Error
          next
        end
        raise Error, "could not find the latest Quick crossword"
      end

      # Finds the puzzle JSON whatever element carries it, so a change in the page's
      # wrapper doesn't break us.
      def extract(html)
        Nokogiri::HTML(html).css("*").each do |node|
          node.attributes.each_value do |attr|
            next unless attr.value.start_with?("{") && attr.value.include?("entries")

            found = find_puzzle(JSON.parse(attr.value))
            return found if found
          rescue JSON::ParserError
            next
          end
        end
        raise Error, "no crossword data found on the puzzle page"
      end

      def parse(data)
        entries = data.fetch("entries")
        cells = {}
        entries.each do |entry|
          x = entry.dig("position", "x")
          y = entry.dig("position", "y")
          entry.fetch("length").times do |i|
            cells[entry["direction"] == "across" ? [x + i, y] : [x, y + i]] ||= nil
          end
          cells[[x, y]] = entry["number"]
        end

        Crossword.new(
          title: Text.squish(data["name"].to_s).then { |t| t.empty? ? "Quick crossword" : t },
          setter: data.dig("creator", "name"),
          date: data["date"] && Time.at(data["date"] / 1000),
          cols: data.dig("dimensions", "cols"), rows: data.dig("dimensions", "rows"),
          cells: cells,
          across: clues(entries, "across"), down: clues(entries, "down")
        )
      rescue KeyError, NoMethodError => e
        raise Error, "unexpected crossword data (#{e.message})"
      end

      private

      def find_puzzle(node)
        case node
        when Hash
          return node if node.key?("entries") && node.key?("dimensions")

          node.each_value { |v| (found = find_puzzle(v)) && (return found) }
          nil
        when Array
          node.each { |v| (found = find_puzzle(v)) && (return found) }
          nil
        end
      end

      def clues(entries, direction)
        entries.select { |e| e["direction"] == direction }.sort_by { |e| e["number"] }.map do |entry|
          text = Text.html_to_text(entry["clue"])
          text = "#{text} (#{enumeration(entry)})" unless text.match?(ENUMERATION)
          [entry["humanNumber"] || entry["number"].to_s, text]
        end
      end

      def enumeration(entry)
        marks = (entry["separatorLocations"] || {}).flat_map { |char, spots| spots.map { |spot| [spot, char] } }.sort
        out = +""
        previous = 0
        marks.each do |spot, char|
          out << "#{spot - previous}#{char}"
          previous = spot
        end
        out << (entry["length"] - previous).to_s
      end
    end
  end
end
