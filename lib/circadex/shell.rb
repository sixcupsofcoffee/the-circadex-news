require "open3"
require "timeout"

module Circadex
  module Shell
    class Error < StandardError; end

    module_function

    # Returns [combined output, success?].
    def run(*command, timeout: 120)
      output, status = Timeout.timeout(timeout) { Open3.capture2e(*command) }
      [output, status.success?]
    rescue Errno::ENOENT
      raise Error, "#{command.first} was not found"
    rescue Timeout::Error
      raise Error, "#{command.first} timed out after #{timeout}s"
    end
  end
end
