# @deckyard/epub

[![test](https://github.com/deckyard/deck-epub/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-epub/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-epub/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-epub)](https://github.com/deckyard/deck-epub/releases/latest)

Read and write EPUB books in a [Jennifer](https://jennifer-lang.dev/)
program, in pure Jennifer. Writing builds EPUB 3.3 (with an optional EPUB 2
`toc.ncx`) from XHTML or Markdown chapters, a cover, pictures and a
stylesheet, deterministically: the same book gives the same bytes, stored or
(optionally) deflated, left-to-right or right-to-left, reflowable or
fixed-layout, with landmarks and a page list. Batch builders add many
chapters or pictures in one call, and `check` lists links in the book that
lead nowhere; `rename` moves a file and the links to it, and `writable`
makes a read book (EPUB 2 chapters, fixed-layout comics, media overlays)
one `build` writes cleanly. Reading takes EPUB
2 and 3 files and returns the metadata, the chapters in reading order, the
table of contents, the other files, the landmarks and page list, the
fixed-layout settings and each chapter as plain text; chapters that are not
well-formed XML are read as HTML, common faults (a declared legacy charset,
a missing or case-mismatched file, an imperfect `mimetype`) are tolerated
and listed in the book's `notes`, and DRM-protected books are refused with a
catchable error.

**[Documentation](https://deckyard.github.io/deck-epub/)**

## Install

```sh
jvc add @deckyard/epub
```

This vendors the deck to `vendor/<scope>/epub/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-epub-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/epub/" as epub;

def b as epub.Book init epub.book("Field Notes", "en");
$b = epub.author($b, "Ada Lovelace");
$b = epub.markdownChapter($b, "one.xhtml", "Observations", "# Observations\n\nThe engine weaves.\n");
fs.writeBytes("notes.epub", epub.build($b));

def back as epub.Book init epub.read(fs.readBytes("notes.epub"));
for (def c in $back.chapters) {
    io.printf("%s\n%s\n", $c.title, epub.text($c));
}
```

## Requirements

Jennifer 0.27.0 or newer. No capability: the deck works on bytes and does no
file, network or process access of its own. It uses the `archive`, `xml`,
`crc`, `hash` and `encoding` libraries and the bundled `markdown` and `html`
modules. Runs on `jennifer-tiny` too, within its smaller nesting and
memory limits (see the reading guide).

## Development

```sh
tools/check-all.sh                 # the full gate, as CI runs it
jennifer test src/epub_test.j      # the test overlays
tools/check-docs.sh                # docs against the code
tools/build-fixtures.sh            # regenerate the Gutenberg fixtures (network)
tools/pack.sh dist                 # build the release archive
```

`tools/check-extra.sh` also validates a built book with
[EPUBCheck](https://www.w3.org/publishing/epubcheck/) when Docker and the
EPUBCheck jar are available (`EPUBCHECK_JAR=/path/to/epubcheck.jar`), and
skips that check otherwise.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

The test fixtures embed Project Gutenberg eBook #1080 (Jonathan Swift, "A
Modest Proposal"), public domain in the USA, distributed under the Project
Gutenberg licence included in the book; see `tools/build-fixtures.sh`.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
