module Circadex
  class Config
    class Error < StandardError; end

    DEFAULTS = {
      "timezone" => "America/New_York",
      "output_dir" => "output",
      "page" => { "width_in" => 7.07, "height_in" => 9.43, "margin_pt" => 30, "body_pt" => 10 },
      "weather" => nil,
      "news" => { "max_age_hours" => 36, "max_paragraphs" => 14, "sections" => [] }
    }.freeze

    def self.load(path)
      raise Error, "config not found: #{path} (copy config.example.yml to config.yml)" unless File.exist?(path)

      new(merge(DEFAULTS, YAML.safe_load_file(path) || {}))
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
