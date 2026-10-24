# The Circadex News

A mini-app that builds a personal daily newspaper as a PDF: weather, news from public feeds, and (soon) mail, site analytics, comics and a crossword. The page size is set up for e-ink tablets, and the output is a single PDF with bookmarks per section.

## Requirements

- Ruby 3.1 or newer (on macOS, install one with Homebrew or rbenv; the system Ruby is too old)
- Bundler

## Setup

```sh
bundle install
cp config.example.yml config.yml   # then edit config.yml
bin/circadex
```

The PDF is written to `output/circadex-YYYY-MM-DD.pdf`. Options:

```
bin/circadex --config path/to/config.yml --out some/dir --date 2026-10-25
```

## Configuration

`config.example.yml` documents every setting. Your real `config.yml` is gitignored, so locations, feed choices and anything else personal stay out of the repository. Credentials (when a source needs them) are read from the macOS Keychain or environment variables, never from the config file.

If a source is unreachable, the paper still builds and the failure is listed on a Notes page at the back.

## Sources

| Source | Status |
| --- | --- |
| Weather (Open-Meteo) | done |
| News and local news (RSS/Atom, full text where the feed or page allows it) | done |
| Mail, analytics, comics, crossword, Sunday edition, tablet upload | planned |

Only fetch content you are entitled to read. Feeds and pages are requested once per run with an identifying User-Agent.

## Tests

```sh
bundle exec rake test
```

Tests use fixtures and make no network requests.

## License

GPL-3.0, see `LICENSE`.
