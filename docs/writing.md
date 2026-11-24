<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Writing a book

A book starts with `book(title, lang)`, takes its parts one call at a time,
and becomes an EPUB™ file with `build`:

```jennifer
import "@deckyard/epub/" as epub;

def b as epub.Book init epub.book("Field Notes", "en");
$b = epub.author($b, "Ada Lovelace");
$b = epub.cover($b, "img/cover.jpg", fs.readBytes("cover.jpg"));
$b = epub.markdownChapter($b, "text/one.xhtml", "Observations", fs.readString("one.md"));
$b = epub.chapter($b, "text/two.xhtml", "Conclusions", '<h1>Conclusions</h1><p>Done.</p>');
fs.writeBytes("notes.epub", epub.build($b));
```

`examples/build_book.j` is a complete program.

## Large books: add parts in batches

From a program that imports the deck, every builder call copies the whole
book: the `Book` crosses into the deck and back, and its structs are rebuilt
each way (`jennifer profile --allocs` lists them as module-boundary
rebuilds). That holds inside a function too; at the top level of a program
with mutable globals each call copies it once more. A book built one part
per call therefore costs time in proportion to the square of its size.

`chapters`, `images` and `tocEntries` add a whole list in one call, so the
book crosses once:

```jennifer
def parts as list of epub.ChapterSource;
for (def name in $names) {
    $parts[] = epub.ChapterSource{
        href: $name + ".xhtml",
        title: $titles[$name],
        body: fs.readString($name + ".md"),
        markdown: true
    };
}
$b = epub.chapters($b, $parts);
$b = epub.images($b, [epub.ImageSource{href: "img/map.png", data: fs.readBytes("map.png")}]);
$b = epub.tocEntries($b, [epub.TocEntry{title: "Maps", href: "maps.xhtml", level: 0}]);
```

Each item is checked as the single builder checks it, and a failing one
leaves the book as it was. 300 chapters and 60 pictures of 200 KB, added
from a function of an importing program: about 0.35 s one call at a time,
0.05 s in two batch calls.

## The book

`book` checks that the title is not blank and that the language is a BCP 47
tag (`en`, `de-AT`, `zh-Hant`), and fills in the rest:

- `identifier`: a `urn:uuid:` derived from the title and language, the same
  on every build. Set the field to use your own (an ISBN URN, say).
- `modified`: `2026-01-01T00:00:00Z`, fixed for the same reason. Set it to
  a real `YYYY-MM-DDThh:mm:ssZ` time if readers should see one.
- a stylesheet, `style.css`, which `stylesheet` replaces.

The reading direction is a field too: `$b.direction = "rtl"` (or `"ltr"`;
`""`, the default, writes none). Set it before adding chapters, like the
language: each chapter's page takes it as the `dir` of its `<html>` when the
chapter is added, and `build` writes it on the navigation document and as
the spine's `page-progression-direction`. `check` reports a chapter added
before it was set.

The other metadata are fields: `description`, `publisher`, `date`. The
date must be a W3C date (W3CDTF): `2020`, `2020-05`, `2020-05-17`, or a day
with a time and zone (`2020-05-17T10:30Z`, `2020-05-17T10:30:05+02:00`);
`build` refuses anything else (reason `"input"`), which EPUBCheck would warn
about.
`author` appends a creator.

```jennifer
$b.description = "Notes on the Analytical Engine.";
$b.publisher = "Self";
$b.date = "1843-09-01";
$b = epub.author($b, "Charles Babbage");
```

## Chapters

Each chapter has an href (its path in the book), a title, and a body.

- `chapter(b, href, title, body)` takes XHTML: the content of `<body>`.
  It must be well formed (`<br/>`, not `<br>`; only the XML entities
  `&amp;` `&lt;` `&gt;` `&quot;` `&apos;` and numeric references, not
  `&nbsp;`), or the call throws reason `"content"` naming the chapter.
  `epub:type` attributes may be used; the page declares the prefix.
- `markdownChapter(b, href, title, md)` renders Markdown (CommonMark plus
  GFM tables, task lists, footnotes) through the bundled `markdown` module.
  Raw HTML in the Markdown is escaped, not passed through.

The deck wraps the body in a page with the title, the language and a link to
the stylesheet, and parses it back to prove it well formed: a chapter that is
not XML fails here, where it can be named, rather than in a reader. Chapters
are read in the order they are added. A chapter that uses SVG, MathML or a
script gets the manifest property EPUB requires (`svg`, `mathml`,
`scripted`).

An href is a relative path of `/`-separated names (`ch01.xhtml`,
`text/part-1/a.xhtml`, `kapitel/übung.xhtml`), kept decoded in the `Book`.
The archive holds the name as it is (UTF-8), and the package, the navigation
document and the NCX write it percent-encoded (`kapitel/%C3%BCbung.xhtml`).
Links you write in a chapter are URLs, so encode them the same way. Refused:
`.` and `..`, a leading `/`, an empty name, a name ending in a dot, control
characters, a backslash and `"*:<>?#` (what OCF forbids in a file name, and
`#`, which starts a fragment), and a space: EPUBCheck warns about a space in
a file name whatever its encoding (PKG-010, "may create interoperability
issues"), and a built book should pass with no warning. Unicode names pass. `nav.xhtml`, `toc.ncx` and
`content.opf` are the deck's own. Two hrefs that differ only in case
(`A.xhtml`, `a.xhtml`) count as the same: EPUB wants file names unique
after case folding, as the book may be unpacked where case is ignored. A chapter in a directory links the
stylesheet as `../style.css`, and its links and pictures are relative to it
in the same way.

A chapter can be left out of the linear reading order (a footnote page):

```jennifer
$b = epub.chapter($b, "notes.xhtml", "Notes", $notesXhtml);
$b.chapters[len($b.chapters) - 1].linear = false;
```

## Pictures, fonts, stylesheets

```jennifer
$b = epub.image($b, "img/map.png", fs.readBytes("map.png"));      # <img src="../img/map.png"/>
$b = epub.file($b, "fonts/serif.woff2", "font/woff2", fs.readBytes("serif.woff2"));
$b = epub.stylesheet($b, fs.readString("book.css"));
```

`image` takes the media type from the extension (`.png`, `.jpg` / `.jpeg`,
`.gif`, `.svg`, `.webp`); `file` takes any file with the media type you give.
`cover` adds a picture and marks it as the cover, both the EPUB 3 way
(`properties="cover-image"`) and the EPUB 2 way (`<meta name="cover">`).
The cover may instead be a page: set `$b.cover` to a chapter's href. An SVG
page gets `cover-image` too; an XHTML page, which that property does not
allow, is named by `<meta name="cover">` and the `cover` landmark. `cover`
stays one field for both, an href, since a book has one cover and readers
look for it in one place; whether it is a picture or a page follows from
what the href names. The
default stylesheet is small on purpose: a reader sets the type and the
margins.

Nothing checks that a chapter's `<img>` points at a picture you added; add
every file a chapter references.

## The table of contents

Without any `tocEntry`, `build` lists every chapter by its title (its href
when the title is blank). Add entries to write your own; once there is one,
the list is yours:

```jennifer
$b = epub.tocEntry($b, "Observations", "text/one.xhtml", 0);
$b = epub.tocEntry($b, "Part Two", "", 0);
$b = epub.tocEntry($b, "Conclusions", "text/two.xhtml", 1);
$b = epub.tocEntry($b, "The last word", "text/two.xhtml#end", 2);
```

The list is flat; `level` nests it. An entry one level deeper than the one
before it is that entry's child. An href `""` makes a heading that only
groups the entries under it, and must have some: `build` refuses a heading
with nothing under it, so a caller that writes a heading per part must drop
the heading of a part with no chapters. `build` refuses (reason
`"toc"`) a level that jumps by more than one, a first entry above 0, a
heading with nothing under it, and an href that is not one of the chapters
(a `#fragment` may follow). A level deeper than 100 (11 on the tiny build, whose value nesting cap of 64 stops the `html` parse of `nav.xhtml` sooner)
is a reached cap,
an `Error` of kind `"limit"`: a navigation document nested that deep is past
what the `html` parser, and so `read`, accepts.

## EPUB 2 readers

```jennifer
$b.ncx = true;
```

writes `toc.ncx` beside `nav.xhtml` and names it in the spine, for readers
that predate EPUB 3. A heading without an href points at its first child,
and entries with the same target share a play order, as the NCX requires.

## What `build` writes

```text
mimetype                    stored, first: application/epub+zip
META-INF/container.xml      points at OEBPS/content.opf
OEBPS/content.opf           metadata, manifest, spine (version 3.0)
OEBPS/nav.xhtml             the table of contents
OEBPS/toc.ncx               when ncx is set
OEBPS/<chapters>            in reading order
OEBPS/<other files>         style.css, pictures, fonts
```

Every entry is stored by default: deflate's output can change with the
toolchain, and a stored archive is the same bytes on every interpreter. Set
`$b.compress = true` for a smaller file: every entry but `mimetype` is then
deflated (one that deflate does not shrink, such as a JPEG, stays stored).
The same interpreter build gives the same bytes; another build of Go's
compressor may give different ones, though always the same book. `read` sets
`compress` when a book has a deflated entry.

The navigation document also carries the landmarks (`<nav
epub:type="landmarks">`, hidden). A book's own, in `$b.landmarks`, are
written as they are; with none, they are generated from the book: `cover`
at the first chapter whose markup has an `epub:type` with `cover` (a page
wrapped in `<section epub:type="cover">`), and `bodymatter` at the first
linear chapter that is not that cover page. There is no generated `toc`
landmark: it would point at the navigation document, which is not in the
spine, and EPUBCheck refuses a landmark into a file outside it (RSC-011). For
the same reason a landmark or page whose target is not a chapter is left out
(`check` reports it). `$b.pages` becomes the navigation document's
`page-list`, the pages of a printed edition:

```jennifer
$b.landmarks = [epub.Landmark{type: "bodymatter", title: "Start", href: "text/one.xhtml"}];
$b.pages = [epub.PageTarget{label: "1", href: "text/one.xhtml#page1"}];
```

`read` returns generated landmarks as none, so a book with none reads back
with none and builds the same bytes again.

## Fixed layout

A comic or a picture book lays out each page itself. The rendition fields
say so for the whole book (`rendition:` metadata in the package), and a
chapter's `spineProperties` overrides them for one page or places it in a
spread:

```jennifer
def b as epub.Book init epub.book("Comic", "ja");
$b.direction = "rtl";
$b.layout = "pre-paginated";      # or "reflowable"
$b.orientation = "portrait";      # "auto", "landscape"
$b.spread = "landscape";          # "none", "portrait", "both", "auto"
$b.viewport = "width=1200, height=1600";
$b = epub.chapter($b, "p1.xhtml", "1", '<img src="img/p1.jpg" alt=""/>');
$b.chapters[0].spineProperties = "page-spread-left";
```

`flow` (`"paginated"`, `"scrolled-continuous"`, `"scrolled-doc"`,
`"auto"`) is the fourth field. A value out of its set is refused by `build`
(reason `"input"`); `""` writes nothing. `viewport` is the `<meta
name="viewport">` a fixed-layout page needs; like `direction`, a chapter
takes it when it is added, so set it first. `spineProperties` is written as
it is.

`check(b)` lists the links that lead nowhere, without refusing anything:
an `href`, `src` or `xlink:href` in a chapter, or a table of contents entry,
whose file is not in the book or whose `#fragment` is no `id` in the chapter
it points into. URLs with a scheme (`https:`, `mailto:`) are not followed.

```jennifer
for (def w in epub.check($b)) {
    io.eprintf("warning: %s\n", $w);
}
fs.writeBytes("notes.epub", epub.build($b));
```

`build` checks the whole book first and throws reason `"input"` for a book
without chapters, an href or manifest id used twice, a `modified` that is
not `YYYY-MM-DDThh:mm:ssZ`, a `direction` other than `""`, `"ltr"` and
`"rtl"`, or a `cover` that is not one of its images.
Books built this way pass [EPUBCheck](https://www.w3.org/publishing/epubcheck/)
without errors or warnings.

## Rebuilding a book that was read

`build` also takes a `Book` from `read`: the chapters are written as they
were read, so read and build of a book this deck wrote gives the same bytes,
as long as its titles, authors and description have no leading, trailing or
repeated whitespace (`read` trims metadata and collapses table of contents
labels the way a reader displays them).
A book from elsewhere may hold what the builders never make. `writable(b)`
returns the book as `build` writes it, every conversion a line in its
`notes`; rebuild a read book with it:

```jennifer
def b as epub.Book init epub.writable(epub.read(fs.readBytes("old.epub")));
for (def n in $b.notes) {
    io.eprintf("note: %s\n", $n);
}
fs.writeBytes("new.epub", epub.build($b));
```

`build` applies the same conversions itself, all but the last one below,
without the notes:

- **An XHTML 1.1 chapter** (an EPUB 2 book's) is written as HTML5: the
  HTML5 doctype instead of the XHTML 1.1 one, and without the `<meta
  http-equiv>` (Content-Type, Content-Style-Type, Content-Script-Type) and
  the table `summary` HTML5 forbids. The text and the rest of the markup
  stay as they are.
- **A navigation document in the spine** stays a chapter, with its content,
  but loses its `nav` property, since `build` writes its own. When it was
  named `nav.xhtml` (or `toc.ncx`, `content.opf`), it is written as
  `nav-old.xhtml` and the links to it are rewritten as `rename` does; an id
  `nav` (or `ncx`, `pub-id`) becomes `nav-old1`.
- **The book's own navigation document, linked from chapters** (an index
  pointing at its entries; `read` keeps it as a file then) becomes a chapter
  out of the reading order, renamed and its links rewritten the same way.
- **A table of contents heading with nothing under it** is left out by
  `writable` only; `build` refuses one, so a builder's mistake stays
  visible.
- **A picture in the spine** (a fixed-layout comic) is wrapped in a
  generated XHTML page beside it (`img/p1.jpg` gets `img/p1.xhtml`, id
  `<id>-page`) that shows it; the picture stays a resource, and table of
  contents entries, landmarks and pages that pointed at it point at the
  page. The page keeps the picture's `spineProperties` (its spread), and in
  a fixed-layout book carries a viewport of the picture's size, read from a
  PNG, GIF or JPEG header (else the book's `viewport`, else
  `width=1000, height=1414`).

A read book whose file names have spaces is refused by `build`. `rename`
moves a chapter or file to a new name and rewrites what points at it: the
links in every chapter, the table of contents, the landmarks, the pages and
the cover (a chapter that changes directory has its own links rewritten
too):

```jennifer
for (def r in $b.resources) {
    if (strings.contains($r.href, " ")) {
        $b = epub.rename($b, $r.href, strings.replace($r.href, " ", "-"));
    }
}
for (def c in $b.chapters) {
    if (strings.contains($c.href, " ")) {
        $b = epub.rename($b, $c.href, strings.replace($c.href, " ", "-"));
    }
}
for (def w in epub.check($b)) {
    io.eprintf("warning: %s\n", $w);
}
```

References `rename` cannot see (a stylesheet's `url(...)`, a script) are
not rewritten. `check` reports every `href` / `src` in a chapter that no
longer resolves.

A read book whose `dc:date` is not a W3C date is refused by `build` until
the date is fixed or cleared (`$b.date = ""`).

`read` is unchanged by this: it is the `Book` going into `build` that is
converted, and `read(build(b)) == b` still holds for every book the builders
make; `writable` changes nothing in such a book.

Media overlays (a narrated book's SMIL files) pass through: each chapter's
`mediaOverlay` (the manifest id of its SMIL file), the SMIL and audio files
among the resources, and the package's `media:` metadata in `mediaMeta`
(`Meta{property, refines, value}`) are read and written back. The deck does
not author overlays, and `build` refuses a `mediaOverlay` that names no SMIL
file of the book.
