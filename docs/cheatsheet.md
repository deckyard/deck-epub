<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# epub cheatsheet

Every export of `@deckyard/epub`. The guides are
[Writing a book](writing.md) and [Reading a book](reading.md).

```jennifer
import "@deckyard/epub/" as epub;
```

Builders return the updated book: `$b = epub.author($b, "Ada")`. Every error
the deck throws itself is an `EpubError` (kind `"epub"`); a reached cap is
kind `"limit"`.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `MIMETYPE` | `"application/epub+zip"` | the content of the `mimetype` entry |
| `ERROR_KIND` | `"epub"` | the `kind` of every `EpubError` |
| `DEFAULT_MAX_BYTES` | `134217728` | the largest EPUB™ `read` takes (128 MiB) |
| `DEFAULT_MAX_ENTRIES` | `10000` | the most files in the archive |
| `DEFAULT_MAX_ENTRY_BYTES` | `67108864` | the largest unpacked file (64 MiB) |
| `DEFAULT_MAX_TOTAL_BYTES` | `268435456` | the most unpacked bytes in all (256 MiB) |

## Writing

| Function | Returns | Does |
|---|---|---|
| `book(title, lang)` | `Book` | a new book with a derived identifier, a fixed `modified` and a default `style.css` |
| `author(b, name)` | `Book` | appends a creator |
| `chapter(b, href, title, body)` | `Book` | appends a chapter from the XHTML of its `<body>`; reason `"content"` when not well formed |
| `markdownChapter(b, href, title, md)` | `Book` | appends a chapter rendered from Markdown |
| `image(b, href, data)` | `Book` | adds a picture; the media type comes from the extension |
| `cover(b, href, data)` | `Book` | adds a picture and marks it as the cover |
| `file(b, href, mediaType, data)` | `Book` | adds any other file (a font, audio) |
| `stylesheet(b, css)` | `Book` | replaces `style.css`, which every chapter links |
| `tocEntry(b, title, href, level)` | `Book` | appends a table of contents line; `href` `""` for a heading |
| `chapters(b, parts)` | `Book` | appends many chapters (`list of ChapterSource`) in one call |
| `images(b, pictures)` | `Book` | adds many pictures (`list of ImageSource`) in one call |
| `tocEntries(b, entries)` | `Book` | appends many table of contents lines (`list of TocEntry`) |
| `rename(b, oldHref, newHref)` | `Book` | renames a chapter or file and rewrites the links, TOC, landmarks, pages and cover pointing at it |
| `check(b)` | `list of string` | warnings for links, sources and `#fragment`s in the book that lead nowhere |
| `writable(b)` | `Book` | the book as `build` writes it, every conversion of a read book noted in `notes` (and empty TOC headings dropped) |
| `build(b)` | `bytes` | the EPUB 3.3 file; `toc.ncx` too when `ncx` is set, deflated when `compress` is |

## Reading

| Function | Returns | Does |
|---|---|---|
| `read(data)` | `Book` | reads an EPUB 2 or 3 file with the default caps |
| `readWith(data, opts)` | `Book` | reads with the caps in `opts` |
| `readOptions()` | `ReadOptions` | the default caps, to adjust |
| `text(c)` | `string` | a chapter as plain text, one paragraph per block |
| `resource(b, href)` | `Resource` | a file of the book by href; reason `"missing"` when absent |
| `resolve(base, href)` | `string` | a link written in the file `base`, as an href |

## Types

### `Book`

| Field | Meaning |
|---|---|
| `title as string` | the title |
| `lang as string` | the language, a BCP 47 tag |
| `identifier as string` | the unique identifier |
| `authors as list of string` | the creators, in order |
| `description as string` | `""` for none |
| `publisher as string` | `""` for none |
| `date as string` | the publication date, `""` for none |
| `modified as string` | `YYYY-MM-DDThh:mm:ssZ`; `""` in a read EPUB 2 book, and `build` then writes `2026-01-01T00:00:00Z` |
| `version as string` | `"3.0"` when built; as declared when read |
| `cover as string` | the cover's href: an image among the resources or a chapter (cover page); `""` for none |
| `chapters as list of Chapter` | the spine, in reading order |
| `toc as list of TocEntry` | the table of contents; when empty, `build` lists the chapters |
| `resources as list of Resource` | every other file |
| `ncx as bool` | `build` also writes `toc.ncx`; `read` sets it when the book has one |
| `direction as string` | `""` (none written), `"ltr"` or `"rtl"`: the pages' `dir` and the spine's `page-progression-direction` |
| `compress as bool` | `build` deflates every entry but `mimetype`; `read` sets it when an entry is deflated |
| `layout as string` | `""`, `"reflowable"` or `"pre-paginated"` (`rendition:layout`) |
| `orientation as string` | `""`, `"auto"`, `"landscape"` or `"portrait"` |
| `spread as string` | `""`, `"none"`, `"landscape"`, `"portrait"`, `"both"` or `"auto"` |
| `flow as string` | `""`, `"paginated"`, `"scrolled-continuous"`, `"scrolled-doc"` or `"auto"` |
| `viewport as string` | a fixed-layout page's `<meta name="viewport">`; chapters take it when added |
| `landmarks as list of Landmark` | the landmarks; empty, `build` generates them |
| `pages as list of PageTarget` | the page list of a printed edition |
| `mediaMeta as list of Meta` | the package's `media:` metadata, for media overlays |
| `notes as list of string` | what `read` tolerated (a declared legacy charset, a missing or case-mismatched file, an imperfect `mimetype`); empty for a well-formed book, ignored by `build` |

### `Chapter`

| Field | Meaning |
|---|---|
| `id as string` | its manifest id |
| `href as string` | its path, relative to the package document, decoded (`a b.xhtml`) |
| `title as string` | its table of contents entry, else its `<title>` |
| `mediaType as string` | `application/xhtml+xml` for XHTML |
| `properties as string` | its manifest properties (`svg`, `mathml`, `scripted`) |
| `content as string` | the whole document; `""` for a picture in the spine |
| `linear as bool` | false for `linear="no"` |
| `wellFormed as bool` | whether the `xml` parser accepts it; false means it is read as HTML |
| `mediaOverlay as string` | the manifest id of its media overlay (SMIL), `""` for none |
| `spineProperties as string` | its spine `itemref` properties (`page-spread-left`, `rendition:layout-pre-paginated`) |

### `ChapterSource`

A chapter for `chapters`.

| Field | Meaning |
|---|---|
| `href as string` | its path in the book |
| `title as string` | its title |
| `body as string` | the XHTML of its `<body>`, or Markdown |
| `markdown as bool` | `body` is Markdown |

### `ImageSource`

A picture for `images`.

| Field | Meaning |
|---|---|
| `href as string` | its path in the book; the media type comes from the extension |
| `data as bytes` | the image file |

### `Landmark`

| Field | Meaning |
|---|---|
| `type as string` | the structural semantic (`cover`, `toc`, `bodymatter`, ...) |
| `title as string` | the label |
| `href as string` | the target, with its `#fragment` |

### `Meta`

| Field | Meaning |
|---|---|
| `property as string` | a `media:` property (`media:duration`, `media:narrator`) |
| `refines as string` | what it refines (`#mo1`), `""` for the book |
| `value as string` | its value |

### `PageTarget`

| Field | Meaning |
|---|---|
| `label as string` | the page number as printed |
| `href as string` | where the page starts, with its `#fragment` |

### `TocEntry`

| Field | Meaning |
|---|---|
| `title as string` | the label |
| `href as string` | a chapter's href with an optional `#fragment`; `""` for a heading |
| `level as int` | the nesting depth, 0 at the top |

### `Resource`

| Field | Meaning |
|---|---|
| `id as string` | its manifest id |
| `href as string` | its path, relative to the package document |
| `mediaType as string` | its media type |
| `properties as string` | its manifest properties (`cover-image`) |
| `data as bytes` | its content; an obfuscated font comes back restored |

### `ReadOptions`

A field at `0` takes the default, a negative one lifts the cap.

| Field | Meaning |
|---|---|
| `maxBytes as int` | the largest EPUB file |
| `maxEntries as int` | the most archive entries |
| `maxEntryBytes as int` | the largest unpacked entry |
| `maxTotalBytes as int` | the most unpacked bytes in all |

### `EpubError`

Thrown, not returned: test `$e.kind == "epub"` before reading `reason`.

| Field | Meaning |
|---|---|
| `kind as string` | `"epub"` |
| `message as string` | what went wrong, starting `epub: ` |
| `reason as string` | `"archive"`, `"container"`, `"package"`, `"drm"`, `"content"`, `"toc"`, `"missing"` or `"input"` |
