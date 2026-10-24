module Circadex
  class Renderer
    # Small bar charts for the traffic report.
    module Charts
      private

      # Vertical bars for a series of [date, value] pairs; the last bar is drawn darkest.
      def bar_chart(series, x, top, width, height)
        values = series.map(&:last)
        return if values.empty?

        peak = [values.max.to_f, 1.0].max
        gap = 2.0
        bar = (width - gap * (values.size - 1)) / values.size
        base = top - height
        pdf.stroke_color INK
        pdf.line_width 0.5
        pdf.stroke_line [x, base], [x + width, base]
        values.each_with_index do |value, i|
          bar_height = value.positive? ? [value / peak * height, 1.5].max : 0
          pdf.fill_color(i == values.size - 1 ? INK : "8A8A8A")
          pdf.fill_rectangle [x + i * (bar + gap), base + bar_height], bar, bar_height if bar_height.positive?
        end
        pdf.fill_color INK
        put(series.first.first.strftime("%b %-d"), x, base - 2, width / 2, size: 6.5, color: MUTED, font: SANS)
        put(series.last.first.strftime("%b %-d"), x + width / 2, base - 2, width / 2, size: 6.5, color: MUTED, font: SANS, align: :right)
      end

      # Rows of label + count with a proportional bar underneath; returns the height used.
      def bar_rows(rows, x, top, width, row_height: 14)
        return 0 if rows.empty?

        peak = [rows.map(&:last).max.to_f, 1.0].max
        rows.each_with_index do |(label, count), i|
          y = top - i * row_height
          number = count.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
          number_width = text_width(number, size: 7, font: SANS) + 4
          put(fit_line(label, width - number_width - 4, size: 7, font: SANS), x, y, width - number_width, size: 7, font: SANS)
          put(number, x + width - number_width, y, number_width, size: 7, style: :bold, font: SANS, align: :right)
          pdf.fill_color "8A8A8A"
          pdf.fill_rectangle [x, y - 9], [count / peak * width, 0.8].max, 2.4
        end
        pdf.fill_color INK
        rows.size * row_height
      end
    end
  end
end
