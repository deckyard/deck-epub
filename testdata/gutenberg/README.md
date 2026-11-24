# Project Gutenberg fixtures

| File | What it is |
| --- | --- |
| `pg1080-epub3.epub` | Project Gutenberg™ eBook #1080, Jonathan Swift, "A Modest Proposal", EPUB 3 with images |
| `pg1080-epub2.epub` | the same book, EPUB 2 without images |

The text is in the public domain. The files are Project Gutenberg's own
downloads, unmodified, with the Project Gutenberg License inside; they are
redistributed here under that licence, free of charge. Project Gutenberg is a
trademark of the Project Gutenberg Literary Archive Foundation.

They stay outside `src/`, so a deck consumer never vendors them. The overlays
that read them return early where `testdata/` is missing, and
`tools/check-extra.sh` fails the gate when they are gone. `tools/build-fixtures.sh`
downloads them again from the gutenberg.pglaf.org mirror.
