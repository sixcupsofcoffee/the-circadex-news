module Circadex
  class Renderer
    # Shared by every page module.
    SERIF = "Serif".freeze
    SANS = "Sans".freeze
    MASTHEAD = "Masthead".freeze
    FONT_DIR = File.expand_path("../../../assets/fonts", __dir__)
    INK = "111111".freeze
    MUTED = "555555".freeze
    FAINT = "999999".freeze

    # Fonts and small text helpers shared by every page.
    module Typography
      private

      def register_fonts
        families = {
          SERIF => family("LiberationSerif"),
          SANS => family("LiberationSans"),
          MASTHEAD => masthead_family
        }
        pdf.font_families.update(families)
        pdf.font SERIF
        @glyphs = {}
        @glyph_font = pdf.find_font(SERIF)
      end

      def family(prefix)
        {
          normal: File.join(FONT_DIR, "#{prefix}-Regular.ttf"), bold: File.join(FONT_DIR, "#{prefix}-Bold.ttf"),
          italic: File.join(FONT_DIR, "#{prefix}-Italic.ttf"), bold_italic: File.join(FONT_DIR, "#{prefix}-BoldItalic.ttf")
        }
      end

      def masthead_family
        configured = @paper["masthead_font"].to_s
        candidates = [configured, File.join(FONT_DIR, "masthead.ttf")].reject(&:empty?)
        path = candidates.find { |c| File.file?(File.expand_path(c)) }
        @custom_masthead = !path.nil?
        return family("LiberationSerif") unless path

        file = File.expand_path(path)
        { normal: file, bold: file, italic: file, bold_italic: file }
      end

      # Drops characters the body font cannot draw (emoji, unusual scripts) rather than printing blanks.
      def clean(str)
        Text.normalize(str).each_char.select { |c| glyph?(c) }.join
      end

      def glyph?(char)
        return true if char == "\n"

        @glyphs.fetch(char) { @glyphs[char] = @glyph_font.glyph_present?(char) }
      end

      # Prawn's font block returns the font, so this hands back the block's own value instead.
      def with_font(font, style)
        result = nil
        pdf.font(font, style: style) { result = yield }
        result
      end

      # Draws text at a fixed position and returns the height it used.
      def put(str, x, y, width, size:, style: :normal, color: INK, font: SERIF, align: :left, leading: 0)
        str = clean(str)
        return 0 if str.empty?

        with_font(font, style) do
          height = pdf.height_of(str, width: width, size: size, leading: leading)
          pdf.fill_color color
          pdf.text_box str, at: [x, y], width: width, height: height + 1, size: size, align: align, leading: leading, overflow: :truncate
          pdf.fill_color INK
          height
        end
      end

      def measure(str, width, size:, style: :normal, font: SERIF, leading: 0)
        str = clean(str)
        return 0 if str.empty?

        with_font(font, style) { pdf.height_of(str, width: width, size: size, leading: leading) }
      end

      def text_width(str, size:, style: :normal, font: SERIF)
        with_font(font, style) { pdf.width_of(clean(str), size: size) }
      end

      # Shortens text with an ellipsis until it fits on one line.
      def fit_line(str, width, size:, style: :normal, font: SERIF)
        str = clean(str)
        str = Text.truncate(str, str.length - 2) while str.length > 4 && text_width(str, size: size, style: style, font: font) > width
        str
      end

      def rule(width, color: INK, at: nil)
        pdf.line_width width
        pdf.stroke_color color
        at ? pdf.stroke_horizontal_line(0, pdf.bounds.width, at: at) : pdf.stroke_horizontal_rule
        pdf.stroke_color INK
      end

      def letterspaced(spacing)
        pdf.character_spacing(spacing) { yield }
      end
    end
  end
end
