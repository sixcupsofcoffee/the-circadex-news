require "test_helper"
require "tmpdir"

class SchedulerTest < Minitest::Test
  def config(hour = 5, minute = 45)
    { "schedule" => { "hour" => hour, "minute" => minute } }
  end

  def scheduler(home, shell: FakeShell.new { |_| ["", true] }, cfg: config)
    Circadex::Scheduler.new(cfg, root: "/Users/me/Dev/the-circadex-news", config_path: "/Users/me/Dev/the-circadex-news/config.yml",
                                 home: home, ruby: "/Users/me/.rbenv/versions/3.2.2/bin/ruby", uid: 501, shell: shell)
  end

  def parse(plist)
    Nokogiri::XML(plist)
  end

  def test_plist_has_schedule_command_and_logs
    Dir.mktmpdir do |home|
      doc = parse(scheduler(home).plist)
      strings = doc.xpath("//string").map(&:text)

      assert_equal "com.circadex.news", strings.first
      assert_includes strings, "/Users/me/Dev/the-circadex-news"
      assert_includes strings, "/Users/me/Dev/the-circadex-news/bin/circadex"
      assert_includes strings, "#{home}/Library/Logs/circadex.log"
      assert_equal %w[5 45], doc.xpath("//key[text()='StartCalendarInterval']/following-sibling::dict[1]/integer").map(&:text)
      assert_match(%r{\A/Users/me/\.rbenv/versions/3\.2\.2/bin:}, strings.find { |s| s.include?(":/opt/homebrew/bin") })
    end
  end

  def test_special_characters_in_paths_are_escaped
    Dir.mktmpdir do |home|
      s = Circadex::Scheduler.new(config, root: "/Users/a&b/<repo>", config_path: "/x/config.yml", home: home, ruby: "/usr/bin/ruby")

      assert_nothing_raised_xml s.plist
      assert_includes parse(s.plist).xpath("//string").map(&:text), "/Users/a&b/<repo>"
    end
  end

  def test_install_writes_plist_and_bootstraps_launchd
    Dir.mktmpdir do |home|
      shell = FakeShell.new { |_| ["", true] }
      path = scheduler(home, shell: shell).install

      assert File.exist?(path)
      assert_equal "#{home}/Library/LaunchAgents/com.circadex.news.plist", path
      assert_equal [["launchctl", "bootout", "gui/501/com.circadex.news"], ["launchctl", "bootstrap", "gui/501", path]], shell.calls
    end
  end

  def test_install_reports_launchctl_failure_but_ignores_missing_old_job
    Dir.mktmpdir do |home|
      shell = FakeShell.new { |cmd| cmd[1] == "bootstrap" ? ["Bootstrap failed: 5", false] : ["not loaded", false] }

      error = assert_raises(Circadex::Shell::Error) { scheduler(home, shell: shell).install }
      assert_match(/bootstrap failed/, error.message)
    end
  end

  def test_uninstall_removes_the_plist
    Dir.mktmpdir do |home|
      s = scheduler(home)
      s.install
      s.uninstall

      refute File.exist?(s.plist_path)
    end
  end

  private

  def assert_nothing_raised_xml(xml)
    assert_empty Nokogiri::XML(xml) { |c| c.strict }.errors
  end
end
