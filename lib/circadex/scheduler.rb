require "cgi"
require "fileutils"
require "rbconfig"

module Circadex
  # Builds and installs a launchd job that runs the paper every morning. The job's paths come
  # from this machine at install time, so nothing personal is stored in the repository.
  class Scheduler
    LABEL = "com.circadex.news".freeze

    def initialize(config, root:, config_path:, home: Dir.home, ruby: RbConfig.ruby, uid: Process.uid, shell: Shell)
      @hour = config["schedule"]["hour"].to_i
      @minute = config["schedule"]["minute"].to_i
      @root = File.expand_path(root)
      @config_path = File.expand_path(config_path)
      @home = home
      @ruby = ruby
      @uid = uid
      @shell = shell
    end

    def plist_path
      File.join(@home, "Library", "LaunchAgents", "#{LABEL}.plist")
    end

    def log_path
      File.join(@home, "Library", "Logs", "circadex.log")
    end

    def plist
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>#{esc(LABEL)}</string>
          <key>ProgramArguments</key>
          <array>#{arguments.map { |a| "\n    <string>#{esc(a)}</string>" }.join}
          </array>
          <key>WorkingDirectory</key><string>#{esc(@root)}</string>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Hour</key><integer>#{@hour}</integer>
            <key>Minute</key><integer>#{@minute}</integer>
          </dict>
          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key><string>#{esc(path_env)}</string>
          </dict>
          <key>StandardOutPath</key><string>#{esc(log_path)}</string>
          <key>StandardErrorPath</key><string>#{esc(log_path)}</string>
        </dict>
        </plist>
      XML
    end

    def install
      FileUtils.mkdir_p([File.dirname(plist_path), File.dirname(log_path)])
      File.write(plist_path, plist)
      launchctl("bootout", "gui/#{@uid}/#{LABEL}", allow_failure: true)
      launchctl("bootstrap", "gui/#{@uid}", plist_path)
      plist_path
    end

    def uninstall
      launchctl("bootout", "gui/#{@uid}/#{LABEL}", allow_failure: true)
      File.delete(plist_path) if File.exist?(plist_path)
    end

    private

    def arguments
      bundle = File.join(File.dirname(@ruby), "bundle")
      runner = File.exist?(bundle) ? [bundle] : ["/usr/bin/env", "bundle"]
      runner + ["exec", "ruby", File.join(@root, "bin", "circadex"), "--config", @config_path]
    end

    def path_env
      [File.dirname(@ruby), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].uniq.join(":")
    end

    def launchctl(*args, allow_failure: false)
      output, ok = @shell.run("launchctl", *args)
      raise Shell::Error, "launchctl #{args.first} failed: #{output.strip[0, 200]}" unless ok || allow_failure
    end

    def esc(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
