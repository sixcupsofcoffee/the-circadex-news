require "net/imap"

module Circadex
  module Sources
    # Read-only IMAP access. The mailbox is opened with EXAMINE and bodies are
    # fetched with PEEK, so nothing is marked as read.
    class ImapClient
      Raw = Struct.new(:uid, :received, :raw)

      BODY_BYTES = 65_536

      def initialize(host:, port:, username:, password:, mailbox: "INBOX", max_fetch: 300)
        @host = host
        @port = port
        @username = username
        @password = password
        @mailbox = mailbox
        @max_fetch = max_fetch
      end

      def fetch_since(midnight)
        imap = Net::IMAP.new(@host, port: @port, ssl: true)
        begin
          imap.login(@username, @password)
          imap.examine(@mailbox)
          # SINCE is date-only and server-timezone dependent, so ask for a day early
          # and let the caller filter by exact time.
          uids = imap.uid_search(["SINCE", (midnight - 86_400).strftime("%-d-%b-%Y")]).last(@max_fetch)
          return [] if uids.empty?

          imap.uid_fetch(uids, ["UID", "INTERNALDATE", "BODY.PEEK[]<0.#{BODY_BYTES}>"]).to_a.filter_map { |data| raw_from(data) }
        ensure
          imap.logout rescue nil
          imap.disconnect rescue nil
        end
      rescue Net::IMAP::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error => e
        raise Inbox::Error, "could not read mail (#{e.class})"
      end

      private

      def raw_from(data)
        attr = data.attr
        body = attr.find { |key, _| key.to_s.start_with?("BODY[]") }&.last
        return unless body

        Raw.new(attr["UID"], received_time(attr["INTERNALDATE"]), body)
      end

      def received_time(value)
        return value if value.is_a?(Time)

        Time.strptime(value.to_s, "%d-%b-%Y %H:%M:%S %z")
      end
    end
  end
end
