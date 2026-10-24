require "test_helper"

class ImapClientTest < Minitest::Test
  Data = Struct.new(:attr)

  class FakeImap
    attr_reader :calls

    def initialize(uids: [], fetched: [], fail_login: false)
      @uids = uids
      @fetched = fetched
      @fail_login = fail_login
      @calls = []
    end

    def login(*) = (@fail_login ? raise(Net::IMAP::NoResponseError, Struct.new(:data).new(Struct.new(:text).new("bad"))) : @calls << :login)
    def examine(box) = @calls << [:examine, box]
    def uid_search(criteria) = (@calls << [:search, criteria]; @uids)
    def uid_fetch(uids, attrs) = (@calls << [:fetch, uids, attrs]; @fetched)
    def logout = @calls << :logout
    def disconnect = @calls << :disconnect
  end

  def client
    Circadex::Sources::ImapClient.new(host: "imap.example.test", port: 993, username: "u", password: "p")
  end

  def with_imap(fake, &block)
    Net::IMAP.stub(:new, fake, &block)
  end

  def test_opens_mailbox_read_only_and_peeks_bodies
    fetched = [Data.new({ "UID" => 7, "INTERNALDATE" => "24-Oct-2026 03:00:00 -0400", "BODY[]<0>" => "From: a@x.test\r\n\r\nhi" })]
    fake = FakeImap.new(uids: [7], fetched: fetched)

    raws = with_imap(fake) { client.fetch_since(Time.new(2026, 10, 24)) }

    assert_equal 1, raws.size
    assert_equal 7, raws.first.uid
    assert_equal Time.parse("2026-10-24 03:00:00 -0400"), raws.first.received
    assert_includes fake.calls, [:examine, "INBOX"]
    assert_equal ["SINCE", "23-Oct-2026"], fake.calls.find { |c| c.is_a?(Array) && c.first == :search }.last
    assert_includes fake.calls.find { |c| c.is_a?(Array) && c.first == :fetch }.last, "BODY.PEEK[]<0.65536>"
    assert_equal %i[logout disconnect], fake.calls.last(2)
  end

  def test_empty_day_returns_nothing
    assert_empty with_imap(FakeImap.new) { client.fetch_since(Time.new(2026, 10, 24)) }
  end

  def test_login_failure_is_wrapped_and_still_disconnects
    fake = FakeImap.new(fail_login: true)

    error = assert_raises(Circadex::Sources::Inbox::Error) { with_imap(fake) { client.fetch_since(Time.new(2026, 10, 24)) } }
    assert_match(/could not read mail/, error.message)
    assert_includes fake.calls, :disconnect
  end
end
