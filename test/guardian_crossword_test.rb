require "test_helper"

class GuardianCrosswordTest < Minitest::Test
  include Fixtures

  RSS = "https://www.theguardian.com/crosswords/series/quick/rss".freeze
  SERIES = "https://www.theguardian.com/crosswords/series/quick".freeze
  PUZZLE = "https://www.theguardian.com/crosswords/quick/17101".freeze

  def source(responses, config = {})
    Circadex::Sources::GuardianCrossword.new(config, http: FakeHttp.new(responses))
  end

  def test_fetches_latest_puzzle_from_the_rss_index
    puzzle = source(RSS => fixture("crossword_rss.xml"), PUZZLE => fixture("crossword_old.html")).fetch

    assert_equal "Quick crossword No 17,101", puzzle.title
    assert_equal "Pan", puzzle.setter
    assert_equal [5, 5], [puzzle.cols, puzzle.rows]
  end

  def test_falls_back_to_the_series_page_when_rss_fails
    puzzle = source({ SERIES => fixture("crossword_series.html"), PUZZLE => fixture("crossword_old.html") }).fetch

    assert_equal 5, puzzle.cols
  end

  def test_configured_number_skips_the_index
    http = FakeHttp.new("https://www.theguardian.com/crosswords/quick/17050" => fixture("crossword_old.html"))
    Circadex::Sources::GuardianCrossword.new({ "number" => 17_050 }, http: http).fetch

    assert_equal ["https://www.theguardian.com/crosswords/quick/17050"], http.requests
  end

  def test_grid_cells_and_numbers
    puzzle = source({ RSS => fixture("crossword_rss.xml"), PUZZLE => fixture("crossword_old.html") }).fetch

    assert_equal 21, puzzle.cells.size
    assert_equal 1, puzzle.cells[[0, 0]]
    assert_equal 2, puzzle.cells[[2, 0]]
    assert_equal 3, puzzle.cells[[4, 0]]
    assert_equal 4, puzzle.cells[[0, 2]]
    assert_equal 5, puzzle.cells[[0, 4]]
    assert_nil puzzle.cells[[1, 0]]
    refute puzzle.cells.key?([1, 1])
  end

  def test_clues_sorted_with_enumerations_added_only_when_missing
    puzzle = source({ RSS => fixture("crossword_rss.xml"), PUZZLE => fixture("crossword_old.html") }).fetch

    assert_equal [["1", "Greeting from a sailor (5)"], ["4", "Fruit with a core (5)"], ["5", "Cart pulled by oxen (2,3)"]], puzzle.across
    assert_equal %w[1 2 3], puzzle.down.map(&:first)
  end

  def test_reads_the_island_wrapper_too
    puzzle = source({ RSS => fixture("crossword_rss.xml"), PUZZLE => fixture("crossword_island.html") }).fetch

    assert_equal 21, puzzle.cells.size
  end

  def test_missing_data_raises_a_clear_error
    error = assert_raises(Circadex::Sources::GuardianCrossword::Error) do
      source({ RSS => fixture("crossword_rss.xml"), PUZZLE => "<html><body>no puzzle</body></html>" }).fetch
    end
    assert_match(/no crossword data/, error.message)
  end

  def test_no_index_reachable_raises
    assert_raises(Circadex::Sources::GuardianCrossword::Error) { source({}).fetch }
  end
end
