require "mail"

module Circadex
  module Sources
    # Turns the day's mail into a digest: what needs attention, real mail,
    # newsletters, and a count of promotions that were left out.
    class Inbox
      class Error < StandardError; end

      Parsed = Struct.new(:from, :address, :subject, :received, :text, :bulk, keyword_init: true)

      ALERT_WORDS = [
        "bill", "invoice", "statement", "payment", "past due", "overdue", "due (today|tomorrow|soon|on)",
        "autopay", "security alert", "suspicious", "fraud", "verification code", "password", "sign-?in",
        "appointment", "delivery", "delivered", "out for delivery", "receipt"
      ].freeze

      PROMO_WORDS = [
        "\\d+% off", "% off", "sale", "deal(s)?", "save \\$?\\d+", "coupon", "limited time", "free shipping",
        "exclusive offer", "discount", "last chance", "ends (today|tonight|soon)", "don't miss", "flash"
      ].freeze

      def initialize(config, client:, now: Time.now)
        @config = config
        @client = client
        @now = now
        @alert = word_regex(config["alert_keywords"] || ALERT_WORDS)
        @promo = word_regex(config["promo_keywords"] || PROMO_WORDS)
        @priority = Array(config["priority_senders"]).map(&:downcase)
      end

      def digest
        midnight = Time.new(@now.year, @now.month, @now.day)
        parsed = @client.fetch_since(midnight).filter_map { |raw| parse(raw) }
                        .select { |m| m.received >= midnight }
                        .sort_by { |m| -m.received.to_i }

        grouped = parsed.group_by { |m| category(m) }
        kept = %i[priority alert personal newsletter].flat_map { |c| grouped.fetch(c, []) }
        limit = @config["max_messages"].to_i.positive? ? @config["max_messages"].to_i : 60

        build_digest(kept, grouped.fetch(:promo, []).size, limit)
      end

      private

      def build_digest(kept, skipped, limit)
        shown = kept.sort_by { |m| -m.received.to_i }.first(limit)
        messages = shown.map { |m| to_message(m) }
        MailDigest.new(
          attention: messages.select { |m| %i[priority alert].include?(m.category) },
          messages: messages.select { |m| m.category == :personal },
          newsletters: messages.select { |m| m.category == :newsletter },
          skipped: skipped,
          total: kept.size + skipped,
          truncated: kept.size > shown.size
        )
      end

      def category(msg)
        return :priority if @priority.any? { |s| msg.address.downcase.include?(s) }
        return :alert if msg.subject.match?(@alert)
        return :promo if msg.bulk && "#{msg.subject} #{msg.text[0, 200]}".match?(@promo)

        msg.bulk ? :newsletter : :personal
      end

      def to_message(msg)
        category = category(msg)
        MailMessage.new(
          from: msg.from, address: msg.address, subject: msg.subject, received: msg.received,
          snippet: Text.truncate(msg.text, snippet_chars(category)), category: category
        )
      end

      def snippet_chars(category)
        { personal: 500, newsletter: 160 }.fetch(category, 400).then { |n| (@config["snippet_chars"] || n).to_i.clamp(0, n) }
      end

      def parse(raw)
        mail = ::Mail.read_from_string(raw.raw)
        sender = mail[:from]&.addrs&.first
        return unless sender

        Parsed.new(
          from: Text.squish(sender.display_name || sender.address),
          address: sender.address.to_s,
          subject: Text.squish(mail.subject.to_s).then { |s| s.empty? ? "(no subject)" : s },
          received: raw.received,
          text: body_text(mail),
          bulk: bulk?(mail)
        )
      rescue StandardError => e
        Circadex.logger.warn("skipping an unreadable message (#{e.class})")
        nil
      end

      def bulk?(mail)
        !mail["List-Unsubscribe"].nil? || mail["Precedence"].to_s.match?(/bulk|list|junk/i)
      end

      def body_text(mail)
        text = if mail.text_part
                 mail.text_part.decoded
               elsif mail.html_part
                 Text.html_to_text(mail.html_part.decoded)
               elsif mail.multipart?
                 ""
               elsif mail.mime_type.to_s.include?("html")
                 Text.html_to_text(mail.body.decoded)
               else
                 mail.body.decoded
               end
        Text.squish(text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(%r{https?://\S+}, ""))
      rescue StandardError
        ""
      end

      def word_regex(words)
        Regexp.new("\\b(#{Array(words).join('|')})", Regexp::IGNORECASE)
      end
    end
  end
end
