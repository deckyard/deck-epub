# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# epub - the shared core: the book model, the error, the constants, and the
# path and media type helpers the writer and the reader both use.

/** The content of the `mimetype` entry every EPUB opens with. */
export def const MIMETYPE as string init "application/epub+zip";

/** The `kind` of every error this deck throws itself (a cap is `"limit"`). */
export def const ERROR_KIND as string init "epub";

/** The largest EPUB `read` accepts, in bytes (128 MiB). */
export def const DEFAULT_MAX_BYTES as int init 134217728;

/** The most archive entries `read` accepts. */
export def const DEFAULT_MAX_ENTRIES as int init 10000;

/** The largest single unpacked entry `read` accepts, in bytes (64 MiB). */
export def const DEFAULT_MAX_ENTRY_BYTES as int init 67108864;

/** The most unpacked bytes, all entries together, `read` accepts (256 MiB). */
export def const DEFAULT_MAX_TOTAL_BYTES as int init 268435456;

def const XHTML_NS as string init "http://www.w3.org/1999/xhtml";
def const OPS_NS as string init "http://www.idpf.org/2007/ops";
def const DC_NS as string init "http://purl.org/dc/elements/1.1/";
def const OPF_NS as string init "http://www.idpf.org/2007/opf";
def const OCF_NS as string init "urn:oasis:names:tc:opendocument:xmlns:container";
def const NCX_NS as string init "http://www.daisy.org/z3986/2005/ncx/";
def const ENC_NS as string init "http://www.w3.org/2001/04/xmlenc#";

def const XHTML_TYPE as string init "application/xhtml+xml";
def const NCX_TYPE as string init "application/x-dtbncx+xml";
def const OPF_TYPE as string init "application/oebps-package+xml";

# The identifier and timestamp of a built book are fixed rather than taken
# from a clock, so the same book gives the same bytes.
def const FIXED_MODIFIED as string init "2026-01-01T00:00:00Z";

/**
 * An EPUB failure. Every error this deck throws itself is one of these, so
 * `reason` is safe to read once `kind` is `"epub"`.
 *
 * @field kind {string} always `"epub"`
 * @field message {string} what went wrong, starting with `epub: `
 * @field reason {string} the class of failure: `"archive"`, `"container"`,
 *   `"package"`, `"drm"`, `"content"`, `"toc"`, `"missing"` or `"input"`
 * @example
 *   try {
 *       def b as epub.Book init epub.read($data);
 *   } catch (e) {
 *       if ($e.kind == "epub" and $e.reason == "drm") {
 *           io.printf("this book is DRM-protected\n");
 *       }
 *   }
 */
export def struct EpubError {
    kind as string,
    message as string,
    reason as string
};

/**
 * One chapter: a document in the spine, in reading order. A picture placed
 * in the spine itself (a fixed-layout book) is a chapter with no content
 * and `wellFormed` false; its bytes are among the book's resources.
 *
 * @field id {string} its manifest id
 * @field href {string} its path relative to the package document
 * @field title {string} its title: the table of contents entry that points
 *   at it, else its `<title>`, else `""`
 * @field mediaType {string} its media type, `application/xhtml+xml` for XHTML
 * @field properties {string} its manifest properties (`"svg"`, `"scripted"`,
 *   ...), space separated
 * @field content {string} the whole document source, `""` for a picture
 * @field linear {bool} false for a spine item marked `linear="no"`
 * @field wellFormed {bool} whether the `xml` parser accepts the document;
 *   false means it is read as HTML
 * @field spineProperties {string} the properties of its spine `itemref`,
 *   space separated: a fixed-layout override (`rendition:layout-pre-paginated`,
 *   `rendition:spread-none`, ...) or a page spread (`page-spread-left`,
 *   `page-spread-right`); `""` for none. Read and written as they are
 * @field mediaOverlay {string} the manifest id of its media overlay (a
 *   SMIL file among the resources), `""` for none. Read and written back;
 *   the deck does not author overlays
 */
export def struct Chapter {
    id as string,
    href as string,
    title as string,
    mediaType as string,
    properties as string,
    content as string,
    linear as bool,
    wellFormed as bool,
    spineProperties as string,
    mediaOverlay as string
};

/**
 * One line of the table of contents. The list is flat: `level` gives the
 * nesting, 0 at the top, and an entry one level deeper than the one before it
 * is that entry's child.
 *
 * @field title {string} the label
 * @field href {string} the target relative to the package document, with
 *   its `#fragment`; `""` for a heading that only groups its children
 * @field level {int} the nesting depth, 0 at the top
 */
export def struct TocEntry {
    title as string,
    href as string,
    level as int
};

/**
 * A landmark: a structural place in the book a reader can jump to, from the
 * EPUB 3 `<nav epub:type="landmarks">` or the EPUB 2 `<guide>`.
 *
 * @field type {string} what the place is, an EPUB 3 structural semantic
 *   (`cover`, `toc`, `bodymatter`, `titlepage`, ...); a `<guide>` type is
 *   mapped to it where one corresponds (`text` is `bodymatter`), else kept
 * @field title {string} the label
 * @field href {string} the target relative to the package document, with
 *   its `#fragment`
 */
export def struct Landmark {
    type as string,
    title as string,
    href as string
};

/**
 * A `media:` metadata entry of the package, as media overlays use them
 * (`media:duration`, `media:active-class`, `media:narrator`), kept so a
 * book with overlays is written back with them.
 *
 * @field property {string} the property, such as `media:duration`
 * @field refines {string} what it refines (`#mo-ch1`), `""` for the book
 * @field value {string} its value (`0:32:29.000`)
 */
export def struct Meta {
    property as string,
    refines as string,
    value as string
};

/**
 * A page break of a printed edition the book follows, from the EPUB 3
 * `<nav epub:type="page-list">` or the NCX `<pageList>`.
 *
 * @field label {string} the page number or name as printed (`"12"`, `"xiv"`)
 * @field href {string} where the page starts, relative to the package
 *   document, with its `#fragment`
 */
export def struct PageTarget {
    label as string,
    href as string
};

/**
 * A file of the book that is not a chapter: an image, a stylesheet, a font.
 *
 * @field id {string} its manifest id
 * @field href {string} its path relative to the package document
 * @field mediaType {string} its media type
 * @field properties {string} its manifest properties (`"cover-image"`, ...)
 * @field data {bytes} its content; an obfuscated font is returned restored
 */
export def struct Resource {
    id as string,
    href as string,
    mediaType as string,
    properties as string,
    data as bytes
};

/**
 * A book, as `book` starts it and `read` returns it.
 *
 * @field title {string} the title
 * @field lang {string} the language, a BCP 47 tag such as `en`
 * @field identifier {string} the unique identifier; `book` derives one from
 *   the title and language
 * @field authors {list of string} the creators, in order
 * @field description {string} the description, `""` for none
 * @field publisher {string} the publisher, `""` for none
 * @field date {string} the publication date, `""` for none
 * @field modified {string} the `dcterms:modified` timestamp,
 *   `YYYY-MM-DDThh:mm:ssZ`; `""` when a read book has none, and `build`
 *   then writes `2026-01-01T00:00:00Z`
 * @field version {string} the package version: `"3.0"` for a built book, as
 *   declared for a read one (`"2.0"`, `"3.0"`)
 * @field cover {string} the href of the cover: an image among the
 *   resources, or a chapter that is the cover page (an SVG or XHTML page in
 *   the spine); `""` for none
 * @field chapters {list of Chapter} the spine, in reading order
 * @field toc {list of TocEntry} the table of contents; when empty, `build`
 *   lists every chapter
 * @field resources {list of Resource} every other file: not the chapters,
 *   the navigation document or the NCX (which `toc` stands for), nor a
 *   remote resource
 * @field ncx {bool} `build` also writes an EPUB 2 `toc.ncx`; `read` sets it
 *   when the book carries one
 * @field direction {string} the reading direction: `""` (the default, none
 *   written), `"ltr"` or `"rtl"`. Chapters take it when they are added, as
 *   the `dir` of their `<html>`; `build` writes it on the navigation document
 *   and as the spine's `page-progression-direction`, where `read` takes it
 *   from
 * @field compress {bool} `build` deflates every entry but `mimetype` (an
 *   entry deflate does not shrink stays stored); false, the default, stores
 *   them all. `read` sets it when an entry of the book is deflated
 * @field layout {string} the fixed-layout rendition of the whole book:
 *   `""` (none written, the default), `"reflowable"` or `"pre-paginated"`
 *   (`rendition:layout`)
 * @field orientation {string} `""`, `"auto"`, `"landscape"` or `"portrait"`
 *   (`rendition:orientation`)
 * @field spread {string} `""`, `"none"`, `"landscape"`, `"portrait"`,
 *   `"both"` or `"auto"` (`rendition:spread`)
 * @field flow {string} `""`, `"paginated"`, `"scrolled-continuous"`,
 *   `"scrolled-doc"` or `"auto"` (`rendition:flow`)
 * @field viewport {string} the `<meta name="viewport">` content of a
 *   fixed-layout page (`"width=1200, height=1600"`), `""` for none. A
 *   chapter takes it when it is added, as with `direction`; `read` takes it
 *   from the first chapter that has one
 * @field landmarks {list of Landmark} the landmarks. Empty, `build`
 *   generates them (the cover page and the start of the body); `read`
 *   returns empty landmarks that are exactly the generated ones
 * @field pages {list of PageTarget} the page list of a printed edition,
 *   written as the navigation document's `page-list`; empty for none
 * @field mediaMeta {list of Meta} the package's `media:` metadata, for
 *   media overlays; empty for none
 * @field notes {list of string} what `read` tolerated in the book (a
 *   legacy charset, a file missing from the archive, a name matched without
 *   regard to case, an imperfect `mimetype`), one line each; empty for a
 *   book that keeps to the format, and for every book `book` starts. `build`
 *   ignores it
 */
export def struct Book {
    title as string,
    lang as string,
    identifier as string,
    authors as list of string,
    description as string,
    publisher as string,
    date as string,
    modified as string,
    version as string,
    cover as string,
    chapters as list of Chapter,
    toc as list of TocEntry,
    resources as list of Resource,
    ncx as bool,
    direction as string,
    compress as bool,
    layout as string,
    orientation as string,
    spread as string,
    flow as string,
    viewport as string,
    landmarks as list of Landmark,
    pages as list of PageTarget,
    mediaMeta as list of Meta,
    notes as list of string
};

/**
 * A chapter for `chapters`: what `chapter` or `markdownChapter` takes.
 *
 * @field href {string} its path in the book (`text/ch01.xhtml`)
 * @field title {string} its title, for the page and the table of contents
 * @field body {string} the XHTML of its `<body>`, or Markdown when
 *   `markdown` is set
 * @field markdown {bool} `body` is Markdown, rendered as `markdownChapter`
 *   renders it
 */
export def struct ChapterSource {
    href as string,
    title as string,
    body as string,
    markdown as bool
};

/**
 * A picture for `images`: what `image` takes.
 *
 * @field href {string} its path in the book (`img/map.png`); the media type
 *   comes from the extension
 * @field data {bytes} the image file
 */
export def struct ImageSource {
    href as string,
    data as bytes
};

/**
 * The caps `readWith` applies. A field at `0` takes its default, a negative
 * one disables the cap; start from `readOptions()`.
 *
 * @field maxBytes {int} the largest EPUB accepted, in bytes
 * @field maxEntries {int} the most archive entries
 * @field maxEntryBytes {int} the largest unpacked entry, in bytes
 * @field maxTotalBytes {int} the most unpacked bytes, all entries together
 */
export def struct ReadOptions {
    maxBytes as int,
    maxEntries as int,
    maxEntryBytes as int,
    maxTotalBytes as int
};

# Throw the deck's error. The reason is the class a caller can act on; the
# message is for people.
func fail(reason as string, message as string) {
    throw EpubError{kind: ERROR_KIND, message: "epub: " + $message, reason: $reason};
}

# A caught error that is a generic kind (a cap, a timeout, a cancelled task)
# passes on unchanged rather than being rewrapped as "epub".
func isGeneric(kind as string) {
    return $kind == "limit" or $kind == "timeout" or $kind == "cancelled" or $kind == "closed";
}

func bytesOf(text as string) {
    return encoding.encode("utf-8", $text);
}

# A short, printable rendering of a name for a message.
func shown(s as string) {
    def out as string init $s;
    if (len($out) > 120) {
        $out = $out[..120] + "...";
    }
    return '"' + $out + '"';
}

# --- paths inside the archive -------------------------------------------
#
# Zip names and hrefs are always `/`-separated, whatever the host, so these
# are written here rather than taken from `path`, which uses the host's
# separator.

# The directory part of a path, "" for a name at the root.
func dirOf(p as string) {
    def at as int init strings.lastIndexOf($p, "/");
    if ($at < 0) {
        return "";
    }
    return $p[..$at];
}

# Resolve "." and ".." segments. A ".." that would climb above the root is
# kept, so the caller can tell a path that escapes.
func cleanPath(p as string) {
    def out as list of string;
    for (def seg in strings.split($p, "/")) {
        if ($seg == "" or $seg == ".") {
            continue;
        }
        if ($seg == ".." and len($out) > 0 and $out[len($out) - 1] != "..") {
            $out = $out[..len($out) - 1];
            continue;
        }
        $out[] = $seg;
    }
    return strings.join($out, "/");
}

# Whether a cleaned path climbs above the root: a leading `..` segment, not
# a name that only starts with two dots (`..notes.xhtml`).
func climbsOut(p as string) {
    return $p == ".." or strings.startsWith($p, "../");
}

func joinPath(dir as string, rel as string) {
    if ($dir == "" or strings.startsWith($rel, "/")) {
        return cleanPath($rel);
    }
    return cleanPath($dir + "/" + $rel);
}

# Split "a.xhtml#frag" into the path and the fragment with its "#".
func splitFragment(href as string) {
    def at as int init strings.indexOf($href, "#");
    if ($at < 0) {
        return [$href, ""];
    }
    return [$href[..$at], $href[$at..]];
}

# An href the writer accepts: a relative path of `/`-separated names, kept
# decoded in the Book (`a b.xhtml`, `kapitel/übung.xhtml`) and percent-encoded
# where it is written as a URL. Refused: an empty name, `.` and `..` (nothing
# climbs out of the package directory), a leading `/`, and what OCF forbids
# in a file name (EPUBCheck PKG-009): control characters, DEL, `"*:<>?\`, and
# a name ending in a dot. `#` is refused too, since it starts the fragment of
# a table of contents href, and a space, which EPUBCheck warns about in a
# file name (PKG-010) whatever the encoding: a built book is 0/0. With `:`
# refused, no href has a scheme. `read` keeps a book's names as they are;
# `rename` gives one with spaces names `build` takes.
def const HREF_CHARS as string init '^[^ "*:<>?#\\\x00-\x1F\x7F]+$';

func checkHref(href as string, what as string) {
    def ok as bool init $href != "" and regex.matches(HREF_CHARS, $href);
    if ($ok) {
        for (def seg in strings.split($href, "/")) {
            if ($seg == "" or $seg == "." or $seg == ".." or strings.endsWith($seg, ".")) {
                $ok = false;
            }
        }
    }
    if (not $ok) {
        fail(
            "input",
            $what + " href " + shown($href) +
                " is not a relative path of names without spaces, control characters, " +
                'a backslash, "*:<>?# or a trailing dot; rename it (epub.rename)');
    }
}

# An href as a URL: each name percent-encoded (UTF-8; everything but letters,
# digits and `-._~`), a `#fragment` kept as written. Ascii hrefs of the
# old letters-digits-`._-` shape come out unchanged.
func hrefUrl(href as string) {
    def parts as list of string init splitFragment($href);
    if (regex.matches('^[A-Za-z0-9._~/-]*$', $parts[0])) {
        return $href;
    }
    def out as list of string;
    for (def seg in strings.split($parts[0], "/")) {
        $out[] = encoding.toText("uri-percent", bytesOf($seg));
    }
    return strings.join($out, "/") + $parts[1];
}

# What `build` names the files it writes itself.
def const NAV_HREF as string init "nav.xhtml";
def const NCX_HREF as string init "toc.ncx";
def const OPF_HREF as string init "content.opf";
def const CSS_HREF as string init "style.css";

def const MEDIA as map of string to string init {
    "xhtml": "application/xhtml+xml",
    "html": "application/xhtml+xml",
    "htm": "application/xhtml+xml",
    "css": "text/css",
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "gif": "image/gif",
    "svg": "image/svg+xml",
    "webp": "image/webp",
    "ttf": "font/ttf",
    "otf": "font/otf",
    "woff": "font/woff",
    "woff2": "font/woff2",
    "mp3": "audio/mpeg",
    "m4a": "audio/mp4",
    "mp4": "video/mp4",
    "js": "text/javascript",
    "smil": "application/smil+xml",
    "ncx": "application/x-dtbncx+xml",
    "txt": "text/plain"
};

# The media type for a file name's extension, "" when it has none known.
func mediaOf(name as string) {
    def base as string init strings.lower($name);
    def slash as int init strings.lastIndexOf($base, "/");
    if ($slash >= 0) {
        $base = $base[$slash + 1..];
    }
    def dot as int init strings.lastIndexOf($base, ".");
    if ($dot < 0) {
        return "";
    }
    def ext as string init $base[$dot + 1..];
    if (not maps.has(MEDIA, $ext)) {
        return "";
    }
    return MEDIA[$ext];
}

func isImage(mediaType as string) {
    return strings.startsWith($mediaType, "image/");
}

# Whether a space-separated property list holds one property.
func hasProperty(properties as string, name as string) {
    for (def p in strings.split($properties, " ")) {
        if ($p == $name) {
            return true;
        }
    }
    return false;
}

# A space-separated property list without one property.
func withoutProperty(properties as string, name as string) {
    if (not hasProperty($properties, $name)) {
        return $properties;
    }
    def out as list of string;
    for (def p in strings.split($properties, " ")) {
        if ($p != "" and $p != $name) {
            $out[] = $p;
        }
    }
    return strings.join($out, " ");
}
