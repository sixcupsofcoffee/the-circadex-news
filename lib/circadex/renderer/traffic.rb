module Circadex
  class Renderer
    # The site traffic page: one report per chosen Cloudflare Web Analytics site.
    module Traffic
      TRAFFIC_HEAD = 13
      TRAFFIC_NUMBERS = 23
      TRAFFIC_ROWS_HEAD = 11
      TRAFFIC_ROW = 14

      private

      def traffic_page(digest)
        return if digest.sites.empty?

        pdf.start_new_page
        section_start("Site Traffic", "traffic")
        section_band("Site Traffic")
        pdf.text clean("#{digest.date.strftime('%A, %B %-d')}  ·  Cloudflare Web Analytics, counts are estimates"), size: 8, style: :italic, color: MUTED

        wide = digest.sites.size == 1
        gap = 18.0
        width = wide ? pdf.bounds.width : (pdf.bounds.width - gap) / 2
        chart = wide ? 80 : 44
        rows = wide ? 8 : 6
        slices = wide ? digest.sites.each_slice(1) : digest.sites.each_slice(2)
        slices.each do |group|
          height = group.map { |site| traffic_site_height(site, pages: rows, referrers: rows, chart: chart) }.max
          room(height + 24)
          pdf.move_down 14
          top = pdf.cursor
          group.each_with_index do |site, i|
            traffic_site(site, i * (width + gap), top, width, pages: rows, referrers: rows, chart: chart)
          end
          pdf.move_cursor_to(top - height)
        end
      end

      def traffic_site_height(site, pages:, referrers:, chart:)
        return TRAFFIC_HEAD + 16 unless site.views

        height = TRAFFIC_HEAD + TRAFFIC_NUMBERS
        height += chart + 13 if show?("trend") && !site.history.to_a.empty?
        height += TRAFFIC_ROWS_HEAD + [site.pages.size, pages].min * TRAFFIC_ROW + 4 if show?("pages") && pages.positive? && !site.pages.empty?
        height += TRAFFIC_ROWS_HEAD + [site.referrers.size, referrers].min * TRAFFIC_ROW + 4 if show?("referrers") && referrers.positive? && !site.referrers.empty?
        height + 4
      end

      # Draws one site's report and returns the height it used.
      def traffic_site(site, x, top, width, pages:, referrers:, chart:)
        put(site.name, x, top, width, size: 9.5, font: SANS, style: :bold)
        return TRAFFIC_HEAD + put(site.notice.to_s, x, top - TRAFFIC_HEAD, width, size: 8, style: :italic, color: MUTED) + 3 unless site.views

        change = Sources::Analytics.change(site.views, site.average_views)
        put(format("%+d%% vs 7-day avg", change), x, top, width, size: 7.4, font: SANS, color: MUTED, align: :right) if change

        y = top - TRAFFIC_HEAD
        views = number(site.views)
        put(views, x, y, width, size: 18, style: :bold)
        put("page views", x + text_width(views, size: 18, style: :bold) + 4, y - 8, 80, size: 7.5, font: SANS, color: MUTED)
        put("#{number(site.visits)} visits", x, y - 6, width, size: 8.5, font: SANS, color: MUTED, align: :right)
        y -= TRAFFIC_NUMBERS

        if show?("trend") && !site.history.to_a.empty?
          bar_chart(site.history, x, y, width, chart)
          y -= chart + 13
        end
        y -= traffic_rows(x, y, width, "Top pages", site.pages.first(pages)) if show?("pages") && pages.positive?
        y -= traffic_rows(x, y, width, "Referrers", site.referrers.first(referrers)) if show?("referrers") && referrers.positive?
        top - y + 4
      end

      def traffic_rows(x, y, width, title, rows)
        return 0 if rows.empty?

        put(title.upcase, x, y, width, size: 6.2, font: SANS, style: :bold, color: MUTED)
        bar_rows(rows, x, y - TRAFFIC_ROWS_HEAD, width, row_height: TRAFFIC_ROW)
        TRAFFIC_ROWS_HEAD + rows.size * TRAFFIC_ROW + 4
      end

      def show?(metric)
        @analytics_show.include?(metric)
      end

      def number(value)
        value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end
    end
  end
end
