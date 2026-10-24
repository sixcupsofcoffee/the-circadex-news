require "open3"
require "tmpdir"

module Circadex
  # Prawn embeds JPEG and PNG only, so other formats are converted first.
  module ImageFile
    module_function

    def kind(bytes)
      head = bytes.to_s.b[0, 12].to_s
      return :png if head.start_with?("\x89PNG".b)
      return :jpeg if head.start_with?("\xFF\xD8".b)
      return :gif if head.start_with?("GIF8".b)
      return :webp if head[0, 4] == "RIFF".b && head[8, 4] == "WEBP".b

      nil
    end

    def printable(bytes, converter: method(:convert))
      case kind(bytes)
      when :png, :jpeg then bytes
      when :gif, :webp then converter.call(bytes)
      end
    end

    # Uses sips (macOS) or ImageMagick; returns PNG bytes or nil when no tool works.
    def convert(bytes)
      Dir.mktmpdir("circadex") do |dir|
        source = File.join(dir, "source")
        target = File.join(dir, "target.png")
        File.binwrite(source, bytes)
        commands(source, target).each do |command|
          _, status = Open3.capture2e(*command)
          return File.binread(target) if status.success? && File.exist?(target)
        rescue Errno::ENOENT
          next
        end
      end
      Circadex.logger.warn("no image converter available (install ImageMagick or use macOS sips)")
      nil
    end

    def commands(source, target)
      [
        ["sips", "-s", "format", "png", source, "--out", target],
        ["magick", "#{source}[0]", target],
        ["convert", "#{source}[0]", target]
      ]
    end
  end
end
