require "date"
require "json"
require "logger"
require "time"
require "yaml"

module Circadex
  VERSION = "0.1.0"

  def self.logger
    @logger ||= Logger.new($stderr, level: Logger::INFO, progname: "circadex")
  end
end

require "circadex/models"
require "circadex/config"
require "circadex/text"
require "circadex/http"
require "circadex/shell"
require "circadex/image_file"
require "circadex/secrets"
require "circadex/sources/weather"
require "circadex/sources/feed"
require "circadex/sources/extract"
require "circadex/sources/news"
require "circadex/sources/inbox"
require "circadex/sources/imap_client"
require "circadex/sources/analytics"
require "circadex/sources/cloudflare_client"
require "circadex/sources/comics"
require "circadex/sources/guardian_crossword"
require "circadex/builder"
require "circadex/renderer"
require "circadex/remarkable"
require "circadex/scheduler"
require "circadex/cli"
