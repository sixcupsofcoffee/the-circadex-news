require "fileutils"
require "optparse"

module Circadex
  module CLI
    DEFAULT_CONFIG = "config.yml".freeze

    module_function

    def run(argv)
      options = { config: DEFAULT_CONFIG }
      parser = OptionParser.new do |o|
        o.banner = "Usage: circadex [options]"
        o.on("-c", "--config PATH", "Config file (default: #{DEFAULT_CONFIG})") { |v| options[:config] = v }
        o.on("-o", "--out DIR", "Output directory (overrides config)") { |v| options[:out] = v }
        o.on("-d", "--date YYYY-MM-DD", "Edition date (default: today)") { |v| options[:date] = Date.iso8601(v) }
        o.on("-v", "--version") { puts Circadex::VERSION; return 0 }
      end
      parser.parse!(argv)

      build(options)
    rescue Config::Error, OptionParser::ParseError, Date::Error => e
      warn "circadex: #{e.message}"
      1
    end

    def build(options)
      config = Config.load(options[:config])
      ENV["TZ"] = config["timezone"]
      date = options[:date] || Date.today

      edition = Builder.new(config).build(date)
      dir = options[:out] || config["output_dir"]
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "circadex-#{date.iso8601}.pdf")
      Renderer.new(config).render_file(edition, path)

      puts path
      0
    end
  end
end
