<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/epub

Read and write EPUB books in pure Jennifer. An EPUB is a zip archive of XHTML
chapters plus two XML files: `META-INF/container.xml`, which names the package
document, and the package document (the OPF), which carries the metadata, the
manifest of every file and the spine, the reading order. This deck builds that
archive from a few calls, and reads one back into the same `Book` value.

- **Writing** produces EPUB 3.3, with an optional EPUB 2 `toc.ncx` for older
  readers. Chapters come from XHTML or from Markdown; the deck adds the cover,
  pictures, fonts and the stylesheet, and builds the package and the
  navigation document as XML trees. The same book always gives the same
  bytes: the timestamp is fixed and the identifier is derived from the title
  and language. See [Writing a book](writing.md).
- **Reading** takes EPUB 2 and 3: the metadata, the chapters in reading order,
  the table of contents (EPUB 3 `nav.xhtml` or EPUB 2 `toc.ncx`), the other
  files, and each chapter as plain text. Real-world chapters that are not
  well-formed XML are read as HTML. See [Reading a book](reading.md).

Everything works on bytes: the deck reads and writes no files itself and
needs no capability.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/epub/" as epub;

def b as epub.Book init epub.book("Notes", "en");
$b = epub.markdownChapter($b, "one.xhtml", "One", "# One\n\nHello.\n");
def back as epub.Book init epub.read(epub.build($b));
io.printf("%s\n", epub.text($back.chapters[0]));
```

The trailing slash resolves to the entry module. Builders return the updated
book, so call them as `$b = epub.author($b, "Ada")`.

An `href` is a path inside the book relative to the package document, with
`/` separators: `text/ch01.xhtml`, `img/map.png`. A link inside a chapter is
relative to that chapter, as on the web; `epub.resolve(...)` turns one into
an href.

## Errors

Every error the deck throws itself is an `epub.EpubError`: kind `"epub"`, a
`message`, and a `reason` to act on.

| `reason` | Thrown when |
|---|---|
| `"archive"` | the bytes are not a zip, or it holds an unsafe name (`../x`) or a name twice |
| `"container"` | the `mimetype` entry is missing, compressed or wrong, or `META-INF/container.xml` (or `encryption.xml`) is missing or malformed |
| `"package"` | the package document is malformed or lacks a title, language, unique identifier, manifest or spine, or names a file the archive lacks |
| `"drm"` | the book is DRM-protected (Adobe ADEPT, Readium LCP, Apple FairPlay, or any encryption other than font obfuscation) |
| `"content"` | a chapter is neither UTF-8 nor UTF-16, or a body given to `chapter` is not well-formed XHTML |
| `"toc"` | a `toc.ncx` is malformed, or a table of contents given to `build` does not nest or points outside the chapters |
| `"missing"` | `resource` finds no file with that href |
| `"input"` | a builder or `build` is given something it cannot write (a blank title, a used href, a book without chapters) |

A reached cap is a plain `Error` of kind `"limit"`, as everywhere in
Jennifer. Test `kind` before reading `reason`:

```jennifer
try {
    def b as epub.Book init epub.read($data);
} catch (e) {
    if ($e.kind == "epub" and $e.reason == "drm") {
        io.printf("this book is DRM-protected\n");
    } elseif ($e.kind == "limit") {
        io.printf("this book is too large\n");
    }
}
```

A helper that receives a caught error takes `epub.EpubError`, not `Error`:
a parameter typed `Error` does not accept a struct of another type.
