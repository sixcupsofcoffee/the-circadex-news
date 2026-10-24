require "test_helper"

class SecretsTest < Minitest::Test
  def test_reads_from_environment
    ENV["CIRCADEX_TEST_SECRET"] = "s3cret"
    assert_equal "s3cret", Circadex::Secrets.fetch("TEST_SECRET")
  ensure
    ENV.delete("CIRCADEX_TEST_SECRET")
  end

  def test_missing_secret_says_how_to_set_it
    Circadex::Secrets.stub(:keychain, nil) do
      error = assert_raises(Circadex::Config::Error) { Circadex::Secrets.fetch("NOPE_NOT_SET") }
      assert_match(/CIRCADEX_NOPE_NOT_SET/, error.message)
      assert_match(/security add-generic-password/, error.message)
    end
  end
end
