# Fonts

`Liberation*.ttf` are the Liberation fonts, licensed under the SIL Open Font License 1.1
(see `LICENSE-Liberation.txt`). They are used for body text, headlines and chart labels.

## Masthead (optional)

The paper's name is set in a blackletter ("Old English" style) face when a font file is
present. Download one you like (for example UnifrakturMaguntia or UnifrakturCook from
Google Fonts, both under the SIL OFL), save it here as `masthead.ttf`, and commit it with
its license text. Or point `paper.masthead_font` in `config.yml` at any `.ttf` path.
Without a file the masthead falls back to bold Liberation Serif.
