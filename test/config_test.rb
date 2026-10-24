require "test_helper"
require "tmpdir"

class ConfigTest < Minitest::Test
  def test_merges_over_defaults
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, "page:\n  body_pt: 11\n")
      config = Circadex::Config.load(path)

      assert_equal 11, config["page"]["body_pt"]
      assert_equal 7.07, config["page"]["width_in"]
      assert_equal "America/New_York", config["timezone"]
    end
  end

  def test_missing_file_explains_what_to_do
    error = assert_raises(Circadex::Config::Error) { Circadex::Config.load("/nonexistent/config.yml") }
    assert_match(/config.example.yml/, error.message)
  end

  def test_example_config_is_valid
    config = Circadex::Config.load(File.expand_path("../config.example.yml", __dir__))

    assert_equal 4, config["news"]["sections"].size
    assert config["news"]["sections"].all? { |s| s["feeds"].all? { |f| f["url"].start_with?("https://") } }
  end
end
