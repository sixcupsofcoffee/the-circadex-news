module Circadex
  class Renderer
    # Simple vector weather icons, drawn with lines and fills so they stay crisp on e-ink.
    module Icons
      CLOUD = "C9C9C9".freeze
      STORM_CLOUD = "9A9A9A".freeze

      KINDS = {
        [0, 1] => :clear, [2] => :partly, [3] => :cloudy, [45, 48] => :fog,
        [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82] => :rain,
        [71, 73, 75, 77, 85, 86] => :snow, [95, 96, 99] => :storm
      }.freeze

      private

      def icon_kind(code)
        KINDS.find { |codes, _| codes.include?(code) }&.last || :cloudy
      end

      # Draws an icon inside a size x size box whose top-left corner is (x, top).
      def weather_icon(code, x, top, size)
        case icon_kind(code)
        when :clear then sun(x + size * 0.5, top - size * 0.5, size * 0.22)
        when :partly
          sun(x + size * 0.36, top - size * 0.34, size * 0.17)
          cloud(x + size * 0.12, top - size * 0.12, size * 0.88, CLOUD)
        when :cloudy then cloud(x, top - size * 0.1, size, CLOUD)
        when :fog then fog(x, top, size)
        when :rain
          cloud(x, top - size * 0.02, size, CLOUD)
          rain(x, top, size)
        when :snow
          cloud(x, top - size * 0.02, size, CLOUD)
          snow(x, top, size)
        when :storm
          cloud(x, top - size * 0.02, size, STORM_CLOUD)
          bolt(x, top, size)
        end
        pdf.fill_color INK
        pdf.stroke_color INK
      end

      def sun(cx, cy, radius)
        pdf.stroke_color INK
        pdf.line_width [radius * 0.14, 0.9].max
        pdf.fill_color "FFFFFF"
        pdf.fill_and_stroke_circle [cx, cy], radius
        8.times do |i|
          angle = i * Math::PI / 4
          pdf.stroke_line [cx + Math.cos(angle) * radius * 1.45, cy + Math.sin(angle) * radius * 1.45],
                          [cx + Math.cos(angle) * radius * 1.95, cy + Math.sin(angle) * radius * 1.95]
        end
      end

      # A cloud whose bounding box is s wide and about 0.55 s tall, starting at (x, top).
      def cloud(x, top, s, color)
        base = top - s * 0.58
        pdf.fill_color color
        pdf.fill_circle [x + s * 0.28, base + s * 0.2], s * 0.17
        pdf.fill_circle [x + s * 0.50, base + s * 0.29], s * 0.23
        pdf.fill_circle [x + s * 0.74, base + s * 0.19], s * 0.15
        pdf.fill_rectangle [x + s * 0.2, base + s * 0.2], s * 0.62, s * 0.2
      end

      def rain(x, top, s)
        pdf.stroke_color INK
        pdf.line_width [s * 0.045, 0.9].max
        [0.3, 0.5, 0.7].each_with_index do |dx, i|
          y = top - s * (0.68 + (i.odd? ? 0.06 : 0))
          pdf.stroke_line [x + s * dx, y], [x + s * (dx - 0.07), y - s * 0.2]
        end
      end

      def snow(x, top, s)
        pdf.fill_color INK
        [[0.3, 0.72], [0.52, 0.86], [0.72, 0.72], [0.41, 0.97], [0.62, 0.97]].each do |dx, dy|
          pdf.fill_circle [x + s * dx, top - s * dy], s * 0.035
        end
      end

      def bolt(x, top, s)
        pts = [[0.54, 0.6], [0.4, 0.82], [0.5, 0.82], [0.44, 1.02], [0.66, 0.74], [0.55, 0.74], [0.63, 0.6]]
        pdf.fill_color INK
        pdf.fill_polygon(*pts.map { |dx, dy| [x + s * dx, top - s * dy] })
      end

      def fog(x, top, s)
        pdf.stroke_color INK
        pdf.line_width [s * 0.05, 1.0].max
        [[0.15, 0.85, 0.3], [0.05, 0.75, 0.5], [0.2, 0.9, 0.7]].each do |from, to, dy|
          pdf.stroke_line [x + s * from, top - s * dy], [x + s * to, top - s * dy]
        end
      end
    end
  end
end
