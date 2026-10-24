require "test_helper"

class InboxTest < Minitest::Test
  NOW = Time.new(2026, 10, 24, 6, 0, 0)

  class FakeClient
    def initialize(raws) = @raws = raws
    def fetch_since(_midnight) = @raws
  end

  def raw(from:, subject:, body: "Hello there, this is the body of the message.", at: "2026-10-24 03:00:00", headers: "", html: false)
    type = html ? "text/html" : "text/plain"
    message = "From: #{from}\r\nTo: me@example.test\r\nSubject: #{subject}\r\nDate: Sat, 24 Oct 2026 03:00:00 -0400\r\n" \
              "Content-Type: #{type}; charset=UTF-8\r\n#{headers}\r\n#{body}"
    Circadex::Sources::ImapClient::Raw.new(1, Time.parse(at), message)
  end

  def digest(raws, config = {})
    Circadex::Sources::Inbox.new({ "priority_senders" => ["steampowered.com"] }.merge(config), client: FakeClient.new(raws), now: NOW).digest
  end

  def test_sorts_mail_into_groups
    d = digest([
      raw(from: "Ann <ann@example.test>", subject: "Dinner Friday?"),
      raw(from: "Power Co <billing@power.test>", subject: "Your bill is due Friday", headers: "List-Unsubscribe: <mailto:x@y.test>\r\n"),
      raw(from: "Steam <noreply@steampowered.com>", subject: "Weekend Deal: 75% off", headers: "List-Unsubscribe: <mailto:x@y.test>\r\n"),
      raw(from: "Shop <news@shop.test>", subject: "Flash sale, 40% off everything", headers: "List-Unsubscribe: <mailto:x@y.test>\r\n"),
      raw(from: "The Weekly <hi@weekly.test>", subject: "Issue 42: reading list", headers: "List-Unsubscribe: <mailto:x@y.test>\r\n")
    ])

    assert_equal ["Steam"], d.attention.select { |m| m.category == :priority }.map(&:from)
    assert_equal ["Your bill is due Friday"], d.attention.select { |m| m.category == :alert }.map(&:subject)
    assert_equal ["Dinner Friday?"], d.messages.map(&:subject)
    assert_equal ["Issue 42: reading list"], d.newsletters.map(&:subject)
    assert_equal 1, d.skipped
    assert_equal 5, d.total
    refute d.truncated
  end

  def test_only_mail_since_local_midnight
    d = digest([
      raw(from: "ann@example.test", subject: "Late last night", at: "2026-10-23 23:59:00"),
      raw(from: "ann@example.test", subject: "This morning", at: "2026-10-24 00:01:00")
    ])

    assert_equal ["This morning"], d.messages.map(&:subject)
  end

  def test_newest_first_and_message_cap
    raws = (1..5).map { |i| raw(from: "ann@example.test", subject: "Mail #{i}", at: "2026-10-24 0#{i}:00:00") }
    d = digest(raws, "max_messages" => 3)

    assert_equal ["Mail 5", "Mail 4", "Mail 3"], d.messages.map(&:subject)
    assert d.truncated
    assert_equal 5, d.total
  end

  def test_html_only_mail_becomes_text_without_links
    d = digest([raw(from: "ann@example.test", subject: "Hi", html: true,
                    body: "<html><body><p>See <a href='https://x.test/very/long/link'>this</a> https://x.test/very/long/link now</p></body></html>")])

    assert_equal "See this now", d.messages.first.snippet
  end

  def test_snippets_are_truncated
    d = digest([raw(from: "ann@example.test", subject: "Long", body: "word " * 400)])

    assert_operator d.messages.first.snippet.length, :<=, 501
  end

  def test_unreadable_message_is_skipped_not_fatal
    bad = Circadex::Sources::ImapClient::Raw.new(2, Time.parse("2026-10-24 02:00:00"), "not a message at all")
    d = digest([bad, raw(from: "ann@example.test", subject: "Fine")])

    assert_equal ["Fine"], d.messages.map(&:subject)
  end

  def test_custom_keywords_override_defaults
    d = digest([raw(from: "ann@example.test", subject: "Library book due")], "alert_keywords" => ["book due"])

    assert_equal ["Library book due"], d.attention.map(&:subject)
  end
end
