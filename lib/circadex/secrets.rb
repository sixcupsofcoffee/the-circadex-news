require "open3"

module Circadex
  # Looks up credentials without ever storing them in the repo or config file.
  # Environment variables win, then the macOS Keychain.
  module Secrets
    SERVICE = "circadex-news".freeze

    module_function

    def fetch(name)
      value = ENV["CIRCADEX_#{name}"].to_s
      value = keychain(name) if value.empty?
      return value unless value.to_s.empty?

      raise Config::Error,
            "missing secret #{name}: set CIRCADEX_#{name} or run " \
            "`security add-generic-password -s #{SERVICE} -a #{name} -w`"
    end

    def keychain(name)
      out, status = Open3.capture2("security", "find-generic-password", "-s", SERVICE, "-a", name, "-w", err: File::NULL)
      status.success? ? out.chomp : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
