module Circadex
  # Sends the day's PDF to the reMarkable cloud with rmapi; the tablet picks it up on its next sync.
  class Remarkable
    class Error < StandardError; end

    EDITION = /\Acircadex-(\d{4}-\d{2}-\d{2})\z/

    def initialize(config, shell: Shell)
      @binary = config["rmapi"] || "rmapi"
      @folder = "/#{(config['folder'] || 'The Circadex').delete_prefix('/')}"
      @keep_days = config["keep_days"].to_i
      @shell = shell
    end

    # Each day is a new document, so annotations on earlier editions are never overwritten.
    def publish(pdf_path, date)
      name = File.basename(pdf_path, ".pdf")
      return :exists if names_in_folder.include?(name)

      run("put", pdf_path, @folder)
      Circadex.logger.info("Tablet: uploaded #{name} to #{@folder}")
      cleanup(date)
      :uploaded
    end

    private

    def names_in_folder
      output, ok = @shell.run(@binary, "ls", @folder)
      unless ok
        run("mkdir", @folder)
        return []
      end

      output.lines.filter_map { |line| line[/\A\[f\]\s+(.+?)\s*\z/, 1] }
    rescue Shell::Error => e
      raise Error, e.message
    end

    # Old editions are removed only when keep_days is set, and only ones this app named.
    def cleanup(date)
      return unless @keep_days.positive?

      names_in_folder.each do |name|
        match = EDITION.match(name) or next
        next unless Date.iso8601(match[1]) < date - @keep_days

        run("rm", "#{@folder}/#{name}")
        Circadex.logger.info("Tablet: removed #{name}")
      end
    end

    def run(*args)
      output, ok = @shell.run(@binary, *args)
      return output if ok

      raise Error, "rmapi #{args.first} failed: #{output.lines.last(2).join.strip[0, 200]}"
    rescue Shell::Error => e
      raise Error, e.message
    end
  end
end
