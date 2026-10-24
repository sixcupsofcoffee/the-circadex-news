require "test_helper"
require "tmpdir"

class CliTest < Minitest::Test
  def test_list_sites_prints_names_and_tags_but_never_credentials
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, "timezone: America/New_York\n")
      client = Object.new
      def client.sites = [{ "name" => "blog.example.test", "tag" => "abc123" }, { "name" => "shop.example.test", "tag" => "def456" }]

      output, = capture_io { assert_equal 0, Circadex::CLI.list_sites({ config: path }, client: client) }

      assert_includes output, "blog.example.test  (abc123)"
      assert_includes output, "shop.example.test  (def456)"
      assert_includes output, "analytics.include"
    end
  end

  def test_list_sites_with_no_sites_says_so
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, "timezone: America/New_York\n")
      client = Object.new
      def client.sites = []

      output, = capture_io { Circadex::CLI.list_sites({ config: path }, client: client) }
      assert_includes output, "No Web Analytics sites found"
    end
  end

  def test_missing_config_gives_a_one_line_error
    _, err = capture_io { assert_equal 1, Circadex::CLI.run(["--config", "/nonexistent/config.yml"]) }
    assert_match(/config not found/, err)
  end
end
