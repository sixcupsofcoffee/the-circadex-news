require "test_helper"

# Stands in for Circadex::Shell: records commands and answers from a block.
class FakeShell
  attr_reader :calls

  def initialize(&handler)
    @calls = []
    @handler = handler
  end

  def run(*command, **)
    @calls << command
    @handler.call(command)
  end
end

class RemarkableTest < Minitest::Test
  PDF = "/tmp/out/circadex-2026-10-24.pdf".freeze
  DATE = Date.new(2026, 10, 24)

  def publisher(config = {}, &handler)
    shell = FakeShell.new(&handler)
    [Circadex::Remarkable.new({ "folder" => "The Circadex" }.merge(config), shell: shell), shell]
  end

  def test_uploads_new_edition_to_the_folder
    pub, shell = publisher do |cmd|
      case cmd[1]
      when "ls" then ["[f]\tcircadex-2026-10-23\n", true]
      when "put" then ["", true]
      end
    end

    assert_equal :uploaded, pub.publish(PDF, DATE)
    assert_includes shell.calls, ["rmapi", "put", PDF, "/The Circadex"]
  end

  def test_creates_the_folder_when_missing
    listed = false
    pub, shell = publisher do |cmd|
      case cmd[1]
      when "ls" then listed ? ["", true] : (listed = true; ["not found", false])
      else ["", true]
      end
    end

    assert_equal :uploaded, pub.publish(PDF, DATE)
    assert_includes shell.calls, ["rmapi", "mkdir", "/The Circadex"]
  end

  def test_existing_edition_is_left_alone
    pub, shell = publisher { |cmd| cmd[1] == "ls" ? ["[f]\tcircadex-2026-10-24\n", true] : ["", true] }

    assert_equal :exists, pub.publish(PDF, DATE)
    refute(shell.calls.any? { |c| c[1] == "put" })
  end

  def test_failed_upload_raises_with_rmapi_output
    pub, = publisher { |cmd| cmd[1] == "put" ? ["Error: auth token expired\n", false] : ["", true] }

    error = assert_raises(Circadex::Remarkable::Error) { pub.publish(PDF, DATE) }
    assert_match(/rmapi put failed: Error: auth token expired/, error.message)
  end

  def test_missing_rmapi_raises_a_clear_error
    shell = Object.new
    def shell.run(*) = raise(Circadex::Shell::Error, "rmapi was not found")
    pub = Circadex::Remarkable.new({}, shell: shell)

    assert_raises(Circadex::Remarkable::Error) { pub.publish(PDF, DATE) }
  end

  def test_old_editions_are_removed_only_when_keep_days_is_set
    listing = "[f]\tcircadex-2026-10-01\n[f]\tcircadex-2026-10-20\n[f]\tmy-notes\n[d]\tcircadex-2026-09-01\n"
    pub, shell = publisher("keep_days" => 7) { |cmd| cmd[1] == "ls" ? [listing, true] : ["", true] }
    pub.publish(PDF, DATE)

    removed = shell.calls.select { |c| c[1] == "rm" }
    assert_equal [["rmapi", "rm", "/The Circadex/circadex-2026-10-01"]], removed

    pub, shell = publisher { |cmd| cmd[1] == "ls" ? [listing, true] : ["", true] }
    pub.publish(PDF, DATE)
    refute(shell.calls.any? { |c| c[1] == "rm" })
  end

  def test_custom_binary_path
    pub, shell = publisher("rmapi" => "/opt/bin/rmapi") { |_| ["", true] }
    pub.publish(PDF, DATE)

    assert(shell.calls.all? { |c| c.first == "/opt/bin/rmapi" })
  end
end
