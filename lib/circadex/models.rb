module Circadex
  Day = Struct.new(:date, :high, :low, :summary, :precip, keyword_init: true)
  Forecast = Struct.new(:location, :today, :upcoming, keyword_init: true)
  Item = Struct.new(:title, :url, :source, :author, :published, :summary, :content_html, keyword_init: true)
  Story = Struct.new(:title, :url, :source, :byline, :published, :summary, :paragraphs, keyword_init: true)
  Section = Struct.new(:title, :stories, :briefs, :notice, keyword_init: true)
  MailMessage = Struct.new(:from, :address, :subject, :received, :snippet, :category, keyword_init: true)
  MailDigest = Struct.new(:attention, :messages, :newsletters, :skipped, :total, :truncated, keyword_init: true)
  AnalyticsSite = Struct.new(:name, :views, :visits, :prior_views, :average_views, :pages, :referrers, :notice, keyword_init: true)
  AnalyticsDigest = Struct.new(:date, :sites, keyword_init: true)
  Edition = Struct.new(:date, :forecast, :sections, :mail, :analytics, :notices, keyword_init: true)
end
