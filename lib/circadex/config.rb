module Circadex
  class Config
    class Error < StandardError; end

    DEFAULTS = {
      "timezone" => "America/New_York",
      "output_dir" => "output",
      "page" => { "width_in" => 7.07, "height_in" => 9.43, "margin_pt" => 30, "body_pt" => 10 },
      "weather" => nil,
      "mail" => nil,
      "analytics" => nil,
      "comics" => nil,
      "crossword" => nil,
      "remarkable" => nil,
      "schedule" => { "hour" => 5, "minute" => 45 },
      "news" => { "max_age_hours" => 36, "max_paragraphs" => 14, "sections" => [] }
    }.freeze

    def self.load(path)
      raise Error, "config not found: #{path} (copy config.example.yml to config.yml)" unless File.exist?(path)

      new(merge(DEFAULTS, parse(path)))
    end

    def self.parse(path)
      data = YAML.safe_load_file(path) || {}
      raise Error, "#{path} should contain settings written as `key: value`" unless data.is_a?(Hash)

      data
    rescue Psych::SyntaxError => e
      # Psych reports where the enclosing block starts, not the bad line, so point at likely culprits too.
      raise Error, "#{path} is not valid YAML (#{e.problem || e.message}, in the block starting at line #{e.line})#{suspect_line(path)}"
    end

    def self.suspect_line(path)
      File.readlines(path).each_with_index do |line, index|
        next if line.strip.empty? || line.lstrip.start_with?("#")
        next unless line.include?("\t") || line[/\A */].size.odd?

        return ". Check the indentation near line #{index + 1}: #{line.rstrip.inspect}"
      end
      ". Check that top-level keys start in column 1 and nested keys are indented by two spaces"
    end

    def self.merge(base, over)
      base.merge(over) do |_, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? merge(a, b) : b
      end
    end

    def initialize(data)
      @data = data
    end

    def [](key)
      @data[key]
    end

    def to_h
      @data
    end
  end
end
