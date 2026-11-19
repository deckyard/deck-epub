<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading a book

`read` takes the bytes of an EPUB 2 or 3 file and returns a `Book`:

```jennifer
import "@deckyard/epub/" as epub;

def b as epub.Book init epub.read(fs.readBytes("book.epub"));
io.printf("%s (%s), %d chapters\n", $b.title, $b.lang, len($b.chapters));
for (def c in $b.chapters) {
    io.printf("## %s\n\n%s\n\n", $c.title, epub.text($c));
}
```

`examples/read_book.j` prints a book's metadata, contents, files and the
start of every chapter.

## What comes back

- **Metadata**: `title`, `lang`, `identifier` (the package's unique
  identifier), `authors` (every `dc:creator`, in order), `description`,
  `publisher`, `date`, `modified` (`""` in an EPUB 2 book), and `version`,
  as the package declares it (`"2.0"`, `"3.0"`).
- **`direction`**: `"ltr"` or `"rtl"` from the spine's
  `page-progression-direction`, `""` when it has none (or `default`).
- **`compress`**: true when an entry other than `mimetype` is deflated, so a
  rebuilt book is compressed as the original was.
- **`landmarks`**: the navigation document's `landmarks` (`Landmark{type,
  title, href}`), else the EPUB 2 `<guide>`, its types mapped to EPUB 3
  names where they differ (`text` is `bodymatter`, `title-page` is
  `titlepage`). Landmarks that are exactly the ones `build` generates come
  back as none.
- **Media overlays**: each chapter's `mediaOverlay` (the manifest id of
  its SMIL file, which is among the resources with its audio) and the
  package's `media:` metadata in `mediaMeta`.
- **`pages`**: the navigation document's `page-list`, else (in a book read
  from its NCX) the NCX `<pageList>`, as `PageTarget{label, href}`.
- **Fixed layout**: `layout`, `orientation`, `spread`, `flow` from the
  package's `rendition:` metadata, each chapter's `spineProperties` from its
  spine `itemref`, and `viewport` from the first chapter that declares one.
- **`cover`**: the href of the cover, from the EPUB 3 `cover-image`
  property, else the EPUB 2 `<meta name="cover">` naming a picture or a
  chapter; `""` when there is none. It is a picture among the resources, or
  a chapter (an SVG or XHTML cover page).
  `epub.resource($b, $b.cover)` gets its bytes.
- **`chapters`**: the spine, in reading order. Each `Chapter` has its `id`,
  `href`, `mediaType`, `properties`, `linear` (false for an item marked
  `linear="no"`), `content` (the whole document) and `title`: the first
  table of contents entry pointing at it, else its `<title>`.
- **`toc`**: the table of contents, a flat list of `TocEntry{title, href,
  level}` where `level` gives the nesting. It comes from the EPUB 3
  navigation document (`<nav epub:type="toc">`), else from the EPUB 2
  `toc.ncx`. A heading without a link has href `""`.
- **`resources`**: every other file in the manifest (stylesheets, pictures,
  fonts), with its bytes. The navigation document and the NCX are not among
  them (`toc` stands for them, and `ncx` says whether the book carried one),
  nor is a remote resource (an `https://` audio file), which has no bytes in
  the archive. A navigation document a chapter links into (an index
  pointing at its entries) is the exception: it is kept as a file, with its
  `nav` property, so the links still lead somewhere when the book is
  written again.

Every href is relative to the package document, decoded (`a%20b.xhtml` is
`a b.xhtml`). A link inside a chapter is relative to the chapter;
`resolve` turns it into an href:

```jennifer
def c as epub.Chapter init $b.chapters[3];                  # text/ch03.xhtml
def pic as epub.Resource init epub.resource($b, epub.resolve($c.href, "../img/fig1.png"));
```

## Plain text

`text(chapter)` gives the text of the chapter's `<body>` in reading order:
one paragraph per block (`<p>`, a heading, a list item, a table row) with a
blank line between them, whitespace collapsed as a browser would, `<br/>` as
a line break, `<pre>` as written, and scripts, styles and the `<head>` left
out. HTML entities are decoded: `&nbsp;` becomes U+00A0, `&mdash;` an em
dash. A picture in the spine has no text.

## Strict and lenient

The container and the package are what the book stands on, so they are
read strictly: there must be a `mimetype` entry saying
`application/epub+zip`; `META-INF/container.xml` must be well-formed XML in
the OCF namespace and name a package document; the package document must be
well-formed, in the OPF namespace, with a title, a language, the unique
identifier it names, a manifest, and a non-empty spine of items from the
manifest whose files are in the archive. Anything else is an `EpubError`
naming what is wrong.

## Tolerances, and `notes`

Some faults are common in books that readers open anyway. `read` tolerates
these, and never silently: each one it applies is a line in the book's
`notes`, which is empty for a book that keeps to the format (every book
this deck builds):

- **`mimetype` imperfect in form**: deflated, not the first entry, or
  followed by whitespace or a newline, as long as it says
  `application/epub+zip`. A missing one, or other content, is refused.
- **A legacy charset a document declares**: a chapter or the navigation
  document that is not UTF-8 or UTF-16 and declares an ISO-8859 or Windows
  code page (in its XML declaration, `<meta charset>` or `http-equiv`
  Content-Type) is decoded with it. The package document and the NCX may
  declare one in their XML declaration only. A document that is valid UTF-8
  is read as UTF-8 whatever it declares, since a Latin-1 label on UTF-8 text
  is the common mistake and the other reading would garble it; when it
  declares a legacy charset and is not plain ASCII, that mismatch is a note
  too. Undeclared,
  or in another charset, the document is refused (reason `"content"`, or
  `"package"` / `"toc"`).
- **A manifest item whose file the archive lacks** is left out of the book.
  A spine item that names one is still an error.
- **A manifest href that matches an archive name only when case is
  ignored** reads that file (the href stays as the manifest writes it). If
  several names match, the book is refused.
- **A spine item that is no XHTML or SVG document** (and no picture) with a
  manifest `fallback` is read as the first document down its fallback
  chain. A chain that loops or ends without one is refused (reason
  `"package"`). A picture in the spine stays a picture, fallback or not: the
  fallback of a comic page is usually one generic page for all of them.

```jennifer
def b as epub.Book init epub.read($data);
for (def n in $b.notes) {
    io.eprintf("note: %s\n", $n);
}
```

A manifest href starting with `/` names a file from the container root, as
a URL would; it is not joined to the package document's directory.

Chapters are where real-world books are untidy: HTML entities such as
`&nbsp;`, unclosed `<p>` and `<br>`, stray tags. A chapter the `xml` parser
rejects is not an error. It keeps its content as it is, has `wellFormed`
false, and is read with the bundled `html` parser for its title and its
text. The navigation document is always read that way. A chapter is
UTF-8, UTF-16 with a byte order mark (the encodings XML and EPUB allow), or a
declared legacy charset (above).

A picture placed in the spine itself (a fixed-layout comic) is a chapter
with no content; its bytes are among the resources.

## DRM and obfuscated fonts

A DRM-protected book cannot be read, and `read` says so with reason
`"drm"`: when it carries `META-INF/rights.xml` (Adobe ADEPT),
`META-INF/license.lcpl` (Readium LCP) or `META-INF/sinf.xml` (Apple
FairPlay), or when `META-INF/encryption.xml` lists a file encrypted with
anything but font obfuscation.

Font obfuscation is not DRM: it only stops a font being lifted out of the
book as a file. Both kinds are undone, so a font resource holds the real
font: the IDPF algorithm (the first 1040 bytes XORed with the SHA-1 of the
unique identifier) and Adobe's (the first 1024 bytes XORed with the
identifier's UUID).

## Caps

Every limit is checked before the work it guards, and a reached one is a
plain `Error` of kind `"limit"`:

| Cap | Default | Guards |
|---|---|---|
| `maxBytes` | 128 MiB | the EPUB file itself |
| `maxEntries` | 10000 | the number of files in the archive |
| `maxEntryBytes` | 64 MiB | one file, unpacked |
| `maxTotalBytes` | 256 MiB | all files together, unpacked (a zip bomb) |

`read` uses the defaults; `readWith` takes a `ReadOptions` from
`readOptions()`. A field at `0` takes the default and a negative one lifts
the cap:

```jennifer
def o as epub.ReadOptions init epub.readOptions();
$o.maxBytes = 8 * 1024 * 1024;
def b as epub.Book init epub.readWith($data, $o);
```

The archive is unpacked with the `archive` library, which also refuses a
member named with an absolute path or a `..` segment (a "zip slip") and
symbolic links; the deck turns those into reason `"archive"`. Parsing is
bounded too: the `xml` and `html` parsers cap nesting depth and node count,
and their `"limit"` passes through unchanged. A chapter past the `xml` cap
is read as HTML instead, as long as the `html` parser (512 levels) takes it.

On the tiny build (`jennifer-tiny`, declared and tested) the deck works the
same, within that build's smaller limits: the `xml` parser nests at most 64
levels (1000 on the default build), and the interpreter's value nesting cap
(64) stops the `html` parser at about 31 elements, so a package document,
NCX or chapter deeper than 64 levels is refused as `"limit"` (a chapter is
not read as HTML instead, as on the default build), a chapter body given to
`chapter` may nest about 60 levels, and a table of contents at most 11 (100
on the default build); and
the interpreter allows less memory for copies, so the largest books (2,000
chapters with a navigation document to match, about 36 MB unpacked) stop
with `"limit"` while the bundled `html` module parses that navigation
document.
