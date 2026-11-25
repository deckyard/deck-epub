<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck reads and writes EPUB™ books in pure Jennifer, working on bytes: it
opens no files and needs no capability.

- **Writing** produces EPUB 3.3, with an optional EPUB 2 `toc.ncx` for older
  readers: chapters from XHTML or Markdown, pictures, fonts, a stylesheet, a
  cover, a nested table of contents, landmarks, a page list, right-to-left
  and fixed-layout books.
- **Reading** takes EPUB 2 and 3: metadata, chapters in reading order, the
  table of contents, landmarks, page list, the other files, fixed-layout
  settings, media overlay links, and each chapter as plain text.
- **Rebuilding** a read book is supported: `writable` converts what the
  builders never make, so `build` writes a valid EPUB 3.

Out of scope, on purpose:

- **DRM.** A protected book is refused, never decrypted. Font obfuscation is
  not DRM and is undone.
- **Authoring media overlays.** Overlays a read book carries pass through;
  there is no API to make one.
- **Rendering or reflowing.** `text` gives plain text for search and
  indexing, not a layout.
- **Editing chapters as trees.** A chapter holds its whole document as text;
  callers who need structure parse it themselves.

It is a deck rather than part of the interpreter because nothing in core
needs it and the format keeps moving (EPUB 2, 3.0, 3.3). It is built on core
libraries: `archive` (unpacking), `xml`, `regex`, `crc`, `hash`, `encoding`,
`compress`, and the bundled `markdown` and `html` modules.

## Decisions

- **One `Book` for both directions.** `read` returns the same structure the
  builders make, and `read(build(b))` equals `b` for a book the builders
  made, provided its titles and metadata carry no stray whitespace (the
  reader trims and collapses them as a reading system displays them).
- **Chapters keep their whole document.** A chapter's `content` is built
  once, when it is added, and `build` writes it as it is. Settings that
  shape the page (`direction`, `viewport`) are therefore taken when a
  chapter is added, like the language; `check` reports a chapter added
  before they were set.
- **Markup is built as trees.** The package document, navigation document
  and NCX are `xml` trees encoded at the end, never concatenated text, so a
  title with an ampersand cannot break them. A chapter body is parsed back
  as XML to prove it well formed; an XHTML chapter that is not is refused at
  once, where it can be named.
- **Its own zip writer.** `mimetype` must be the first entry and stored,
  which `archive.pack` cannot express, so the writer lays out the zip itself
  (ported from Grimoire's EPUB renderer). Entries are stored by default:
  stored bytes are the same on every interpreter. `compress` deflates every
  entry but `mimetype`; an entry deflate does not shrink stays stored.
- **Deterministic output.** No clock: a fixed modification time and an
  identifier derived from title and language (the same scheme as Grimoire,
  so a book it built keeps its identifier). The same book gives the same
  bytes.
- **Names.** Hrefs are kept decoded in the `Book` and percent-encoded where
  they are written as URLs. A name with a space is refused by the writer,
  since EPUBCheck warns about spaces in file names whatever the encoding;
  Unicode names are allowed. `rename` gives a read book with spaced names
  names the writer takes, and rewrites the links to them. Names are compared
  ignoring case, as OCF wants them unique after case folding.
- **Strict container, lenient content.** The container, package document
  and NCX are what a book stands on and are read strictly. Chapters and the
  navigation document are read leniently: a chapter that is not well-formed
  XML is kept and read as HTML. A few common faults are tolerated, and
  never silently: each adds a line to the book's `notes` (an imperfect
  `mimetype`, a declared legacy charset, a mislabelled UTF-8 document, a
  manifest file missing from the archive, a name matched ignoring case, a
  spine fallback chain followed).
- **Batch builders.** From a program that imports the deck, each builder
  call rebuilds the whole `Book` at the module boundary, so adding parts one
  at a time costs time in proportion to the square of the book.
  `chapters`, `images` and `tocEntries` add a list in one call; the single
  builders stay for small books.
- **Landmarks.** A book's own landmarks are written as they are; with none,
  `build` generates the cover page and the start of the body. `read`
  returns landmarks that are exactly the generated ones as none, which keeps
  the round trip exact.
- **Cover.** `cover` is one href, naming either a picture among the
  resources or a chapter that is the cover page; what it names decides how
  it is marked (`cover-image` for a picture or an SVG page, `<meta
  name="cover">` and the cover landmark always).
- **Rebuild conversions.** A read book may hold what the builders never
  make; `build` converts it as it writes (its old navigation document in the
  spine or linked from chapters becomes an ordinary chapter, a picture in
  the spine gets a page that shows it, an XHTML 1.1 chapter becomes HTML5).
  `writable` returns the converted book with a note per conversion, and
  also drops table of contents headings with nothing under them, which
  `build` itself refuses so that a builder's mistake stays visible.
- **Fixed layout and overlays pass through.** Rendition metadata, spine
  item properties, viewports, media overlay links and `media:` metadata are
  read and written back as they are, so a rebuilt comic or narrated book
  keeps them.

## Errors

Every error the deck throws itself is an `EpubError`: kind `"epub"`, a
`message` starting `epub: `, and a `reason` to act on: `"archive"`,
`"container"`, `"package"`, `"drm"`, `"content"`, `"toc"`, `"missing"` or
`"input"`. Its fields are safe to read once the kind is `"epub"`.

A reached cap is a plain error of kind `"limit"`, whether the deck's own
(file size, TOC depth, zip without zip64) or one of the `archive`, `xml`
and `html` caps it relies on. Errors from those libraries that are generic
kinds (`"limit"`, `"timeout"`, `"cancelled"`, `"closed"`) pass through
unchanged; anything else they throw is rewrapped as an `EpubError` naming
the file. No message is ever parsed.

## Security and limits

Books are untrusted input.

- **Caps**, all adjustable through `readWith`: the EPUB file (128 MiB), the
  number of archive entries (10,000), one unpacked entry (64 MiB), and all
  unpacked bytes together (256 MiB, against zip bombs). A table of contents
  deeper than 100 levels is refused by the writer.
- **Paths.** `archive` refuses absolute names, `..` segments and special
  files; the deck refuses a duplicate entry, a container or manifest path
  that climbs out of the book, and hrefs the writer would not accept.
- **XML.** The `xml` parser expands no entities, so external entities and
  entity bombs in a package or chapter fail as malformed; its nesting cap
  passes through as `"limit"`.
- **DRM** is detected by the files it leaves (Adobe™ ADEPT, Readium™ LCP,
  Apple™ FairPlay™) or by any encryption besides font obfuscation, and the
  book is refused with reason `"drm"`.
- **Scripts** in chapters are kept and marked `scripted`, never run.

## Testing and validation

The overlays test both directions without a network: hand-made archives
for every error path and tolerance, and Project Gutenberg™ #1080 as EPUB 3
and EPUB 2, read from `testdata/gutenberg/`. Those books stay out of `src/`, so
consumers never vendor them; from a bare copy of `src/` their tests return
early, and `tools/check-extra.sh` makes sure the gate never runs without them.

By hand, on 2026-11-14 and 2026-11-15:

- 73 real books (10 Gutenberg titles as EPUB 3 and EPUB 2, among them
  Chinese and Japanese ones; 8 Standard Ebooks files; the 45 IDPF/W3C
  epub3-samples) were read and compared with an independent reader (Python
  zipfile and lxml): metadata, spine, table of contents, files and the text
  of every chapter match.
- About 30 constructed hostile or broken archives: zip slip, absolute
  names, duplicates, a zip bomb, truncation, entity expansion, deep nesting,
  wrong or misplaced `mimetype`, legacy charsets, UTF-16.
- EPUBCheck 5.4.0 with 0 errors and 0 warnings on books built with every
  writer feature, and on rebuilt samples: Gutenberg EPUB 2 and 3, Standard
  Ebooks, fixed-layout comics, an RTL book, books with media overlays.
- `tools/check-extra.sh` runs EPUBCheck on the example book when a jar and
  Docker™ are available; CI skips it.

Not covered: DRM-free books from commercial stores, Calibre output,
EPUB 3 multiple renditions, and any reading system's rendering.

## Known limitations

- **Rebuild limits.** Rendition settings for spreads are kept, but a
  multiple-rendition package, SMIL references to renamed chapters, and
  references inside stylesheets or scripts to renamed files are not
  rewritten. Links into a navigation document the book replaces only
  survive when `read` kept that document (a chapter links into it).
- **Round trip limits.** A book whose explicit landmarks equal the
  generated ones reads back with none (the bytes are the same). A builder
  book whose chapter links to `nav.xhtml` reads back with the generated
  navigation document as a file.
- **Text.** `text` is a plain-text reading for search, not a renderer:
  CSS, `display`, and generated content are ignored. Very large MathML
  chapters take seconds.
- **Charsets.** UTF-16 is decoded in Jennifer, since `convert` decodes
  UTF-8 only; legacy charsets are only those the `encoding` library knows.
- **Case folding** is lower-casing, exact for ASCII names, close for
  others.
- **`jennifer-tiny`.** The suite passes on the tiny build, which the deck
  declares. Its limits are smaller: `xml` nests 64 levels (a package, NCX
  or chapter deeper is refused), the interpreter's value nesting cap of 64
  stops the `html` parse at about 31 elements (a table of contents is
  written at most 11 levels deep, so its `nav.xhtml` reads back), and less
  memory for copies, so a
  book of about 2,000 chapters stops with "limit" in the `html` parse of its
  navigation document. Walks over trees recurse only a few levels and go on
  with an explicit stack, as the tiny build allows 120 nested calls.

## Dependencies on the interpreter

- Thrown structs keep their fields in a catch, so `EpubError` reaches the
  caller as a struct (the interpreter's thrown-struct milestones).
- `archive.unpackWith` with entry and total caps, `xml` and `html` caps
  that throw kind `"limit"` (the decoder-cap milestone), and the
  `markdown` module's XHTML output.
- A floor of 0.28.0 (the calls 0.29.0 removes are replaced by their 0.28.0 forms), for the UTF-8 codecs of `encoding.encode` / `decode`,
  `strings.replicate` and `testing.assertThrowsArgs`.
