# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# epub - writing a book: the builders and `build`.
#
# Ported from Grimoire's EPUB renderer (plugins/epub.j). Markup is built as a
# tree and encoded, never assembled as text: a title with an ampersand in it,
# concatenated into a `<dc:title>`, produces a file every reader refuses. Each
# chapter body is parsed back for the same reason: well formed is a parser's
# judgement, not a regular expression's.

# Every XML file in the archive opens with this; neither `xml.encode` nor the
# Markdown renderer writes it.
def const DECLARATION as string init '<?xml version="1.0" encoding="utf-8"?>' + "\n";

# A reading stylesheet, deliberately small: a reader sets the type and the
# margins, and a book that fights it reads worse on every device it was not
# tested on.
def const CSS as string init 'body { margin: 0 1em; line-height: 1.5; }
h1, h2, h3, h4 { line-height: 1.25; }
pre { white-space: pre-wrap; word-wrap: break-word; background: #f4f4f4; padding: 0.6em; }
code { font-family: monospace; }
blockquote { margin: 1em 0 1em 1em; padding-left: 0.8em; border-left: 3px solid #ccc; }
table { border-collapse: collapse; }
th, td { border: 1px solid #ccc; padding: 0.3em 0.5em; }
img { max-width: 100%; }
';

# Manifest ids the writer gives its own files, and the metadata id of the
# identifier; nothing else in the package may use them.
def const RESERVED_IDS as list of string init ["nav", "ncx", "pub-id"];

# An XML name, as manifest ids are: a letter (any script) or `_`, then
# letters, digits, `.`, `_` and `-`. Before, ASCII only, which refused the
# Japanese ids of a read book (kusamakura sample).
def const ID_SHAPE as string init '^[\p{L}_][\p{L}\p{N}._-]*$';
# A W3C date (W3CDTF, the profile of ISO 8601 EPUBCheck reads `dc:date`
# with): a year, a month, a day, then a time to the minute or second (with
# fractions) and a zone. Anything else draws EPUBCheck's OPF-053 warning.
def const DATE_SHAPE as string init '^[0-9]{4}(-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01])' +
    '(T([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\.[0-9]+)?)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9]))?)?)?$';

def const MODIFIED_SHAPE as string init '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$';

# --- XML documents -------------------------------------------------------

# A package document, a container: XML no one reads as prose, so indented.
func xmlDocument(root as xml.Value) {
    return DECLARATION + xml.encodePretty($root) + "\n";
}

# A content document: XHTML, not indented. Whitespace between elements is
# text, so a pretty-printer would put spaces into every `<pre>`.
func xhtmlDocument(root as xml.Value) {
    return DECLARATION + "<!DOCTYPE html>\n" + xml.encode($root) + "\n";
}

# The publication identifier: stable across builds of the same book, so not a
# fresh UUID. The digest of the title and language gives the same answer every
# time and a different one for a different book. Grimoire's scheme, kept so a
# book it built keeps its identifier.
func identifierFor(title as string, lang as string) {
    def digest as string init encoding.toText(
        "hex",
        hash.compute("sha256", bytesOf($title + "/" + $lang)));
    return "urn:uuid:" + $digest[0..8] + "-" + $digest[8..12] + "-5" + $digest[13..16] + "-a" +
        $digest[17..20] + "-" + $digest[20..32];
}

# A chapter body, back as nodes. Parsed with the XHTML namespace as the
# default and `epub:` bound, so the body lands in the XHTML namespace and an
# `epub:type` in it is declared by the page around it.
func bodyOf(markup as string, href as string) {
    try {
        return xml.decode("<body>" + $markup + "</body>", {"": XHTML_NS, "epub": OPS_NS});
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("content", "chapter " + shown($href) + " is not well-formed XHTML: " + $e.message);
    }
    return xml.element("body");
}

# The XHTML page every chapter and the navigation document share, around a
# `<body>` that is already a tree. `css` is the stylesheet's href relative to
# the page, `""` for none.
func xhtmlPage(
    lang as string,
    dir as string,
    viewport as string,
    title as string,
    css as string,
    body as xml.Value) {
    def head as xml.Value init xml.element("head");
    $head = xml.append($head, xml.setAttr(xml.element("meta"), "charset", "utf-8"));
    if ($viewport != "") {
        def vp as xml.Value init xml.setAttr(xml.element("meta"), "name", "viewport");
        $head = xml.append($head, xml.setAttr($vp, "content", $viewport));
    }
    $head = xml.append($head, xml.setText(xml.element("title"), $title));
    if ($css != "") {
        def link as xml.Value init xml.setAttr(xml.element("link"), "rel", "stylesheet");
        $link = xml.setAttr($link, "type", "text/css");
        $link = xml.setAttr($link, "href", $css);
        $head = xml.append($head, $link);
    }
    def page as xml.Value init xml.setAttr(xml.element("html"), "xmlns", XHTML_NS);
    $page = xml.setAttr($page, "xmlns:epub", OPS_NS);
    $page = xml.setAttr($page, "xml:lang", $lang);
    $page = xml.setAttr($page, "lang", $lang);
    if ($dir != "") {
        $page = xml.setAttr($page, "dir", $dir);
    }
    $page = xml.append($page, $head);
    $page = xml.append($page, $body);
    return xhtmlDocument($page);
}

# The way from a file at `href` back up to the package directory.
func upTo(href as string) {
    return strings.repeat("../", strings.count($href, "/"));
}

# The manifest properties a content document needs for what it holds.
func contentProperties(markup as string) {
    def out as list of string;
    if (regex.matches('<([A-Za-z][A-Za-z0-9.-]*:)?svg[\s/>]', $markup)) {
        $out[] = "svg";
    }
    if (regex.matches('<([A-Za-z][A-Za-z0-9.-]*:)?math[\s/>]', $markup)) {
        $out[] = "mathml";
    }
    if (regex.matches('<script[\s/>]', $markup)) {
        $out[] = "scripted";
    }
    return strings.join($out, " ");
}

# --- the builders --------------------------------------------------------

# Hrefs are compared case-folded: OCF wants names unique after case folding
# (EPUBCheck OPF-060), since a book is unpacked onto file systems that
# ignore case; lower case stands in for the fold (exact for ASCII names).
#
# A single builder scans the book: it is called with the whole book anyway,
# which crosses the module boundary and is rebuilt on every call, so nothing
# it could index would outlive the call. A batch builder indexes the book
# once in a `Taken` and keeps it up to date as it appends, so adding n parts
# costs one pass, not n scans. Lists are indexed, never iterated: `for (def r
# in $b.resources)` binds a copy of each element, picture bytes included.

# Whether an href is already used by a file of the book or by one `build`
# writes itself, ignoring case.
func hrefTaken(b as Book, href as string) {
    def want as string init strings.lower($href);
    if ($want == NAV_HREF or $want == NCX_HREF or $want == OPF_HREF) {
        return true;
    }
    for (def i in 0..len($b.chapters)) {
        if (strings.lower($b.chapters[$i].href) == $want) {
            return true;
        }
    }
    for (def i in 0..len($b.resources)) {
        if (strings.lower($b.resources[$i].href) == $want) {
            return true;
        }
    }
    return false;
}

func idTaken(b as Book, id as string) {
    if (lists.contains(RESERVED_IDS, $id)) {
        return true;
    }
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].id == $id) {
            return true;
        }
    }
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].id == $id) {
            return true;
        }
    }
    return false;
}

# Whether the book has its stylesheet, `style.css`, for a page to link.
func hasStylesheet(b as Book) {
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href == CSS_HREF) {
            return true;
        }
    }
    return false;
}

# The first free manifest id of the form prefix<n>, prefix<n+1>, ...
func scanFreeId(b as Book, prefix as string, n as int) {
    def k as int init $n;
    while (idTaken($b, $prefix + convert.toString($k))) {
        $k = $k + 1;
    }
    return $prefix + convert.toString($k);
}

func checkHrefFree(b as Book, href as string, what as string) {
    checkHref($href, $what);
    if (hrefTaken($b, $href)) {
        fail("input", $what + " href " + shown($href) + " is already used in this book");
    }
}

# What a book uses, indexed for a batch builder: the hrefs, case-folded, the
# manifest ids, and whether `style.css` is there.
def struct Taken {
    hrefs as map of string to bool,
    ids as map of string to bool,
    css as bool
};

func takenOf(b as Book) {
    def hrefs as map of string to bool init {NAV_HREF: true, NCX_HREF: true, OPF_HREF: true};
    def ids as map of string to bool;
    for (def id in RESERVED_IDS) {
        $ids[$id] = true;
    }
    for (def i in 0..len($b.chapters)) {
        $hrefs[strings.lower($b.chapters[$i].href)] = true;
        $ids[$b.chapters[$i].id] = true;
    }
    for (def i in 0..len($b.resources)) {
        $hrefs[strings.lower($b.resources[$i].href)] = true;
        $ids[$b.resources[$i].id] = true;
    }
    return Taken{hrefs: $hrefs, ids: $ids, css: hasStylesheet($b)};
}

func freeId(t as Taken, prefix as string, n as int) {
    def k as int init $n;
    while (maps.has($t.ids, $prefix + convert.toString($k))) {
        $k = $k + 1;
    }
    return $prefix + convert.toString($k);
}

func checkNewHref(t as Taken, href as string, what as string) {
    checkHref($href, $what);
    if (maps.has($t.hrefs, strings.lower($href))) {
        fail("input", $what + " href " + shown($href) + " is already used in this book");
    }
}

# The builders append what these make, once the href is checked and the id
# chosen. They only read the book, so it is not copied into them; a builder
# that passed the book on to another builder would copy it on every call.

func newResource(href as string, mediaType as string, data as bytes, id as string) {
    return Resource{id: $id, href: $href, mediaType: $mediaType, properties: "", data: $data};
}

# The media type of a picture's href, refused when it is not an image.
func imageMedia(href as string) {
    def media as string init mediaOf($href);
    if (not isImage($media)) {
        fail("input", "image " + shown($href) + " is not .png, .jpg, .gif, .svg or .webp");
    }
    return $media;
}

func newChapter(
    b as Book,
    href as string,
    title as string,
    body as string,
    id as string,
    css as bool) {
    def node as xml.Value init bodyOf($body, $href);
    def label as string init $title;
    if (strings.trim($label) == "") {
        $label = $b.title;
    }
    def link as string init "";
    if ($css) {
        $link = upTo($href) + CSS_HREF;
    }
    return Chapter{
        id: $id,
        href: $href,
        title: $title,
        mediaType: XHTML_TYPE,
        properties: contentProperties($body),
        content: xhtmlPage($b.lang, $b.direction, $b.viewport, $label, $link, $node),
        linear: true,
        wellFormed: true,
        spineProperties: "",
        mediaOverlay: ""
    };
}

func newTocEntry(e as TocEntry) {
    if (strings.trim($e.title) == "") {
        fail("input", "a table of contents entry needs a title");
    }
    if ($e.level < 0) {
        fail("input", "a table of contents level cannot be negative");
    }
    return $e;
}

/**
 * Start a book. It carries a default stylesheet (`style.css`), an identifier
 * derived from the title and language, and a fixed modification time, so the
 * same book always builds to the same bytes.
 *
 * @param title {string} the title, not blank
 * @param lang {string} the language, a BCP 47 tag such as `en` or `de-AT`
 * @return {Book} an empty book
 * @throws {EpubError} reason "input" for a blank title or language
 * @example
 *   def b as epub.Book init epub.book("Notes", "en");
 */
export func book(title as string, lang as string) {
    if (strings.trim($title) == "") {
        fail("input", "a book needs a title");
    }
    if (not regex.matches('^[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*$', $lang)) {
        fail("input", "language " + shown($lang) + " is not a BCP 47 tag");
    }
    def style as Resource init Resource{
        id: "style",
        href: CSS_HREF,
        mediaType: "text/css",
        properties: "",
        data: bytesOf(CSS)
    };
    return Book{
        title: $title,
        lang: $lang,
        identifier: identifierFor($title, $lang),
        authors: [],
        description: "",
        publisher: "",
        date: "",
        modified: FIXED_MODIFIED,
        version: "3.0",
        cover: "",
        chapters: [],
        toc: [],
        resources: [$style],
        ncx: false,
        direction: "",
        compress: false,
        layout: "",
        orientation: "",
        spread: "",
        flow: "",
        viewport: "",
        landmarks: [],
        pages: [],
        mediaMeta: [],
        notes: []
    };
}

/**
 * Add an author (a `dc:creator`), after the ones already there.
 *
 * @param b {Book} the book
 * @param name {string} the author's name, not blank
 * @return {Book} the book with the author
 * @throws {EpubError} reason "input" for a blank name
 */
export func author(b as Book, name as string) {
    if (strings.trim($name) == "") {
        fail("input", "an author needs a name");
    }
    $b.authors[] = $name;
    return $b;
}

/**
 * Add a file of any kind: a font, an audio clip, a second stylesheet. A
 * chapter goes in with `chapter`, a picture with `image`.
 *
 * @param b {Book} the book
 * @param href {string} its path in the book, relative (`fonts/serif.woff2`)
 * @param mediaType {string} its media type, such as `font/woff2`
 * @param data {bytes} its content
 * @return {Book} the book with the file
 * @throws {EpubError} reason "input" for a bad or used href or a blank media type
 */
export func file(b as Book, href as string, mediaType as string, data as bytes) {
    if (not regex.matches('^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+', $mediaType)) {
        fail("input", "media type " + shown($mediaType) + " is not type/subtype");
    }
    checkHrefFree($b, $href, "file");
    $b.resources[] = newResource(
        $href,
        $mediaType,
        $data,
        scanFreeId($b, "res", len($b.resources) + 1));
    return $b;
}

/**
 * Add a picture. Its media type comes from the extension: `.png`, `.jpg` /
 * `.jpeg`, `.gif`, `.svg` or `.webp`. A chapter shows it with
 * `<img src="..."/>`, relative to the chapter.
 *
 * @param b {Book} the book
 * @param href {string} its path in the book (`img/map.png`)
 * @param data {bytes} the image file
 * @return {Book} the book with the picture
 * @throws {EpubError} reason "input" for a bad or used href or an extension
 *   that is not an image
 */
export func image(b as Book, href as string, data as bytes) {
    def media as string init imageMedia($href);
    checkHrefFree($b, $href, "file");
    $b.resources[] = newResource(
        $href,
        $media,
        $data,
        scanFreeId($b, "res", len($b.resources) + 1));
    return $b;
}

/**
 * Add the cover image. It goes into the book like any picture and is marked
 * as the cover (EPUB 3 `cover-image`, and the EPUB 2 `<meta name="cover">`).
 *
 * @param b {Book} the book
 * @param href {string} its path in the book (`cover.jpg`)
 * @param data {bytes} the image file
 * @return {Book} the book with its cover
 * @throws {EpubError} reason "input" for a second cover, a bad or used href,
 *   or an extension that is not an image
 */
export func cover(b as Book, href as string, data as bytes) {
    if ($b.cover != "") {
        fail("input", "the book already has a cover, " + shown($b.cover));
    }
    def media as string init mediaOf($href);
    if (not isImage($media)) {
        fail("input", "cover " + shown($href) + " is not .png, .jpg, .gif, .svg or .webp");
    }
    checkHrefFree($b, $href, "file");
    def r as Resource init newResource(
        $href,
        $media,
        $data,
        scanFreeId($b, "res", len($b.resources) + 1));
    $r.properties = "cover-image";
    if (not idTaken($b, "cover-image")) {
        $r.id = "cover-image";
    }
    $b.resources[] = $r;
    $b.cover = $href;
    return $b;
}

/**
 * Replace the book's stylesheet, `style.css`, which every chapter added with
 * `chapter` or `markdownChapter` links to.
 *
 * @param b {Book} the book
 * @param css {string} the stylesheet
 * @return {Book} the book with the new stylesheet
 */
export func stylesheet(b as Book, css as string) {
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href == CSS_HREF) {
            $b.resources[$i].data = bytesOf($css);
            return $b;
        }
    }
    $b.resources[] = Resource{
        id: scanFreeId($b, "style", 1),
        href: CSS_HREF,
        mediaType: "text/css",
        properties: "",
        data: bytesOf($css)
    };
    return $b;
}

/**
 * Add a chapter from XHTML: the content of its `<body>`, which must be well
 * formed (`<br/>`, not `<br>`; no HTML entities but the XML five and numeric
 * references). The chapter is wrapped in a page with its title and a link to
 * the book's stylesheet, and appended to the reading order. `epub:type`
 * attributes may be used.
 *
 * @param b {Book} the book
 * @param href {string} its path in the book (`ch01.xhtml`, `text/intro.xhtml`)
 * @param title {string} its title, for the page and the table of contents
 * @param body {string} the XHTML of the body
 * @return {Book} the book with the chapter
 * @throws {EpubError} reason "content" for a body that is not well formed,
 *   "input" for a bad or used href
 * @example
 *   $b = epub.chapter($b, "ch01.xhtml", "One", '<h1>One</h1><p>Hello.</p>');
 */
export func chapter(b as Book, href as string, title as string, body as string) {
    checkHrefFree($b, $href, "chapter");
    def id as string init scanFreeId($b, "ch", len($b.chapters) + 1);
    $b.chapters[] = newChapter($b, $href, $title, $body, $id, hasStylesheet($b));
    return $b;
}

/**
 * Add a chapter from Markdown (CommonMark plus GFM, through the bundled
 * `markdown` module). Raw HTML in the Markdown is escaped, not passed
 * through. Pictures it shows are added separately with `image`.
 *
 * @param b {Book} the book
 * @param href {string} its path in the book (`ch01.xhtml`)
 * @param title {string} its title, for the page and the table of contents
 * @param md {string} the Markdown source
 * @return {Book} the book with the chapter
 * @throws {EpubError} reason "input" for a bad or used href
 * @example
 *   $b = epub.markdownChapter($b, "ch01.xhtml", "One", "# One\n\nHello.\n");
 */
export func markdownChapter(b as Book, href as string, title as string, md as string) {
    checkHrefFree($b, $href, "chapter");
    def id as string init scanFreeId($b, "ch", len($b.chapters) + 1);
    $b.chapters[] = newChapter($b, $href, $title, markdown.toXhtml($md), $id, hasStylesheet($b));
    return $b;
}

/**
 * Add many chapters in one call, in order: each as `chapter` adds it, or as
 * `markdownChapter` when its `markdown` is set. One call instead of one per
 * chapter matters in a program that imports the deck: every call into it
 * rebuilds the whole `Book` on the way in and out, so a book built one part
 * at a time costs time in proportion to the square of its size.
 *
 * @param b {Book} the book
 * @param parts {list of ChapterSource} the chapters, in reading order
 * @return {Book} the book with the chapters
 * @throws {EpubError} reason "content" for a body that is not well formed,
 *   "input" for a bad or used href; the book is then unchanged
 * @example
 *   $b = epub.chapters($b, [
 *       epub.ChapterSource{href: "one.xhtml", title: "One", body: "# One\n", markdown: true},
 *       epub.ChapterSource{href: "two.xhtml", title: "Two", body: '<p>Two.</p>', markdown: false}
 *   ]);
 */
export func chapters(b as Book, parts as list of ChapterSource) {
    def t as Taken init takenOf($b);
    for (def i in 0..len($parts)) {
        def body as string init $parts[$i].body;
        if ($parts[$i].markdown) {
            $body = markdown.toXhtml($body);
        }
        checkNewHref($t, $parts[$i].href, "chapter");
        def c as Chapter init newChapter(
            $b,
            $parts[$i].href,
            $parts[$i].title,
            $body,
            freeId($t, "ch", len($b.chapters) + 1),
            $t.css);
        $t.hrefs[strings.lower($c.href)] = true;
        $t.ids[$c.id] = true;
        $b.chapters[] = $c;
    }
    return $b;
}

/**
 * Add many pictures in one call, each as `image` adds it.
 *
 * @param b {Book} the book
 * @param pictures {list of ImageSource} the pictures
 * @return {Book} the book with the pictures
 * @throws {EpubError} reason "input" for a bad or used href or an extension
 *   that is not an image; the book is then unchanged
 */
export func images(b as Book, pictures as list of ImageSource) {
    def t as Taken init takenOf($b);
    for (def i in 0..len($pictures)) {
        def media as string init imageMedia($pictures[$i].href);
        checkNewHref($t, $pictures[$i].href, "file");
        def r as Resource init newResource(
            $pictures[$i].href,
            $media,
            $pictures[$i].data,
            freeId($t, "res", len($b.resources) + 1));
        $t.hrefs[strings.lower($r.href)] = true;
        $t.ids[$r.id] = true;
        $b.resources[] = $r;
    }
    return $b;
}

/**
 * Add a line to the table of contents. Without any, `build` lists every
 * chapter by its title; once one is added, the list is the book's. An entry
 * one level deeper than the one before it is its child; a heading with no
 * target (`href` `""`) must have children.
 *
 * @param b {Book} the book
 * @param title {string} the label
 * @param href {string} a chapter's href, with an optional `#fragment`; `""`
 *   for a heading that only groups the entries under it
 * @param level {int} the nesting depth, 0 at the top
 * @return {Book} the book with the entry
 * @throws {EpubError} reason "input" for a blank title or a negative level
 */
export func tocEntry(b as Book, title as string, href as string, level as int) {
    $b.toc[] = newTocEntry(TocEntry{title: $title, href: $href, level: $level});
    return $b;
}

/**
 * Add many lines to the table of contents in one call, each as `tocEntry`
 * adds it.
 *
 * @param b {Book} the book
 * @param entries {list of TocEntry} the lines, in order
 * @return {Book} the book with the lines
 * @throws {EpubError} reason "input" for a blank title or a negative level;
 *   the book is then unchanged
 * @example
 *   $b = epub.tocEntries($b, [
 *       epub.TocEntry{title: "Part One", href: "", level: 0},
 *       epub.TocEntry{title: "One", href: "one.xhtml", level: 1}
 *   ]);
 */
export func tocEntries(b as Book, entries as list of TocEntry) {
    for (def i in 0..len($entries)) {
        $b.toc[] = newTocEntry($entries[$i]);
    }
    return $b;
}

# --- the package ---------------------------------------------------------

# The one file whose path is fixed by the format: it says where the package
# document is, and nothing else.
func containerXml() {
    def root as xml.Value init xml.setAttr(
        xml.element("rootfile"),
        "full-path",
        "OEBPS/" + OPF_HREF);
    $root = xml.setAttr($root, "media-type", OPF_TYPE);
    def out as xml.Value init xml.setAttr(xml.element("container"), "version", "1.0");
    $out = xml.setAttr($out, "xmlns", OCF_NS);
    return xmlDocument(xml.append($out, xml.append(xml.element("rootfiles"), $root)));
}

# Whether a chapter is the book's cover page and a picture (an SVG page),
# so its manifest item carries `cover-image`.
func isCoverPicture(b as Book, c as Chapter) {
    return $c.href == $b.cover and isImage($c.mediaType);
}

func manifestItem(id as string, href as string, media as string, properties as string) {
    def item as xml.Value init xml.setAttr(xml.element("item"), "id", $id);
    $item = xml.setAttr($item, "href", $href);
    $item = xml.setAttr($item, "media-type", $media);
    if ($properties != "") {
        $item = xml.setAttr($item, "properties", $properties);
    }
    return $item;
}

func dc(name as string, text as string) {
    return xml.setText(xml.element("dc:" + $name), $text);
}

# The manifest id of the cover image, "" when the book has none.
# The manifest id of the cover: the picture's, or the cover page's.
func coverId(b as Book) {
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href == $b.cover) {
            return $b.resources[$i].id;
        }
    }
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].href == $b.cover) {
            return $b.chapters[$i].id;
        }
    }
    return "";
}

func metadataNode(b as Book) {
    def out as xml.Value init xml.setAttr(xml.element("metadata"), "xmlns:dc", DC_NS);
    def id as xml.Value init xml.setText(xml.element("dc:identifier"), $b.identifier);
    $out = xml.append($out, xml.setAttr($id, "id", "pub-id"));
    $out = xml.append($out, dc("title", $b.title));
    $out = xml.append($out, dc("language", $b.lang));
    for (def name in $b.authors) {
        $out = xml.append($out, dc("creator", $name));
    }
    if ($b.description != "") {
        $out = xml.append($out, dc("description", $b.description));
    }
    if ($b.publisher != "") {
        $out = xml.append($out, dc("publisher", $b.publisher));
    }
    if ($b.date != "") {
        $out = xml.append($out, dc("date", $b.date));
    }
    def modified as xml.Value init xml.setAttr(xml.element("meta"), "property", "dcterms:modified");
    def stamp as string init $b.modified;
    if ($stamp == "") {
        $stamp = FIXED_MODIFIED;
    }
    $out = xml.append($out, xml.setText($modified, $stamp));
    for (def r in [
        ["rendition:layout", $b.layout],
        ["rendition:orientation", $b.orientation],
        ["rendition:spread", $b.spread],
        ["rendition:flow", $b.flow]
    ]) {
        if ($r[1] != "") {
            $out = xml.append(
                $out,
                xml.setText(xml.setAttr(xml.element("meta"), "property", $r[0]), $r[1]));
        }
    }
    for (def m in $b.mediaMeta) {
        def meta as xml.Value init xml.setAttr(xml.element("meta"), "property", $m.property);
        if ($m.refines != "") {
            $meta = xml.setAttr($meta, "refines", $m.refines);
        }
        $out = xml.append($out, xml.setText($meta, $m.value));
    }
    if ($b.cover != "") {
        def mark as xml.Value init xml.setAttr(xml.element("meta"), "name", "cover");
        $out = xml.append($out, xml.setAttr($mark, "content", coverId($b)));
    }
    return $out;
}

# The package document: what the book is, what is in it, and in what order it
# is read.
func contentOpf(b as Book) {
    def manifest as xml.Value init xml.element("manifest");
    $manifest = xml.append($manifest, manifestItem("nav", NAV_HREF, XHTML_TYPE, "nav"));
    if ($b.ncx) {
        $manifest = xml.append($manifest, manifestItem("ncx", NCX_HREF, NCX_TYPE, ""));
    }
    def spine as xml.Value init xml.element("spine");
    if ($b.ncx) {
        $spine = xml.setAttr($spine, "toc", "ncx");
    }
    if ($b.direction != "") {
        $spine = xml.setAttr($spine, "page-progression-direction", $b.direction);
    }
    # `build` writes the navigation document itself, and a package names
    # exactly one: a read book whose nav was in its spine keeps it as a
    # chapter, but not as the nav.
    for (def c in $b.chapters) {
        def properties as string init withoutProperty($c.properties, "nav");
        if (isCoverPicture($b, $c) and not hasProperty($properties, "cover-image")) {
            $properties = strings.trim($properties + " cover-image");
        }
        def item as xml.Value init manifestItem($c.id, hrefUrl($c.href), $c.mediaType, $properties);
        if ($c.mediaOverlay != "") {
            $item = xml.setAttr($item, "media-overlay", $c.mediaOverlay);
        }
        $manifest = xml.append($manifest, $item);
        def ref as xml.Value init xml.setAttr(xml.element("itemref"), "idref", $c.id);
        if (not $c.linear) {
            $ref = xml.setAttr($ref, "linear", "no");
        }
        if ($c.spineProperties != "") {
            $ref = xml.setAttr($ref, "properties", $c.spineProperties);
        }
        $spine = xml.append($spine, $ref);
    }
    for (def r in $b.resources) {
        def properties as string init withoutProperty($r.properties, "nav");
        if ($r.href == $b.cover and not hasProperty($properties, "cover-image")) {
            $properties = strings.trim($properties + " cover-image");
        }
        $manifest = xml.append(
            $manifest,
            manifestItem($r.id, hrefUrl($r.href), $r.mediaType, $properties));
    }
    def package as xml.Value init xml.setAttr(xml.element("package"), "xmlns", OPF_NS);
    $package = xml.setAttr($package, "version", "3.0");
    $package = xml.setAttr($package, "unique-identifier", "pub-id");
    $package = xml.setAttr($package, "xml:lang", $b.lang);
    $package = xml.append($package, metadataNode($b));
    $package = xml.append($package, $manifest);
    $package = xml.append($package, $spine);
    return xmlDocument($package);
}

# --- the table of contents -----------------------------------------------

# The table of contents `build` writes: the book's own, or one line per
# chapter.
func tocOf(b as Book) {
    if (len($b.toc) > 0) {
        return $b.toc;
    }
    def out as list of TocEntry;
    for (def c in $b.chapters) {
        def label as string init $c.title;
        if (strings.trim($label) == "") {
            $label = $c.href;
        }
        $out[] = TocEntry{title: $label, href: $c.href, level: 0};
    }
    return $out;
}

# The deepest table of contents level `build` writes. Each level is two
# elements of nav.xhtml (`<li><ol>`), and the `html` parser that reads it
# back stops at 512; deeper, `xml.append` itself refuses the tree (kind
# "limit"). Books
# nest a few levels.
def const MAX_TOC_LEVEL as int init 100;

# Refuse a table of contents a reader could not follow: a level that jumps, a
# heading with nothing under it, a link to something that is not a chapter.
func checkToc(entries as list of TocEntry, chapters as list of Chapter) {
    def hrefs as list of string;
    for (def c in $chapters) {
        $hrefs[] = $c.href;
    }
    def prev as int init -1;
    for (def i in 0..len($entries)) {
        def e as TocEntry init $entries[$i];
        def where as string init "table of contents entry " + shown($e.title);
        if ($e.level > MAX_TOC_LEVEL) {
            throw Error{
                kind: "limit",
                message: "epub: " + $where + " is deeper than level " +
                    convert.toString(MAX_TOC_LEVEL)
            };
        }
        if ($e.level > $prev + 1) {
            fail(
                "toc",
                $where + " is level " + convert.toString($e.level) +
                    " under a level " + convert.toString($prev));
        }
        if ($e.href == "") {
            if ($i + 1 >= len($entries) or $entries[$i + 1].level <= $e.level) {
                fail("toc", $where + " has no target and no entries under it");
            }
        } elseif (not lists.contains($hrefs, splitFragment($e.href)[0])) {
            fail("toc", $where + " points at " + shown($e.href) + ", which is not a chapter");
        }
        $prev = $e.level;
    }
}

func navLabel(e as TocEntry) {
    if ($e.href == "") {
        return xml.setText(xml.element("span"), $e.title);
    }
    return xml.setText(xml.setAttr(xml.element("a"), "href", hrefUrl($e.href)), $e.title);
}

# The `<ol>` of the table of contents, each entry's deeper entries nested in
# its `<li>`. Built with an explicit stack, one open `<ol>` and its last `<li>`
# per level, rather than a call per level: the tiny build allows 120 nested
# calls, and a table of contents may nest 100 levels.
func navList(entries as list of TocEntry) {
    def ols as list of xml.Value;
    def lis as list of xml.Value;
    for (def i in 0..len($entries)) {
        def level as int init $entries[$i].level;
        while (len($ols) > $level + 1) {
            def k as int init len($ols) - 1;
            def inner as xml.Value init xml.append($ols[$k], $lis[$k]);
            $ols = $ols[..$k];
            $lis = $lis[..$k];
            $lis[$k - 1] = xml.append($lis[$k - 1], $inner);
        }
        def li as xml.Value init xml.append(xml.element("li"), navLabel($entries[$i]));
        if (len($ols) == $level + 1) {
            $ols[$level] = xml.append($ols[$level], $lis[$level]);
            $lis[$level] = $li;
        } else {
            $ols[] = xml.element("ol");
            $lis[] = $li;
        }
    }
    while (len($ols) > 1) {
        def k as int init len($ols) - 1;
        def inner as xml.Value init xml.append($ols[$k], $lis[$k]);
        $ols = $ols[..$k];
        $lis = $lis[..$k];
        $lis[$k - 1] = xml.append($lis[$k - 1], $inner);
    }
    if (len($ols) == 0) {
        return xml.element("ol");
    }
    return xml.append($ols[0], $lis[0]);
}

# A chapter that is the cover page: one whose markup carries an `epub:type`
# with the `cover` token (`<section epub:type="cover">`).
def const COVER_TYPE as string init 'epub:type\s*=\s*("([^"]*\s)?cover(\s[^"]*)?"|' +
    "'([^']*\\s)?cover(\\s[^']*)?')";

# The index of the cover page among the chapters, -1 for none.
func coverPage(chapters as list of Chapter) {
    for (def i in 0..len($chapters)) {
        if (regex.matches(COVER_TYPE, $chapters[$i].content)) {
            return $i;
        }
    }
    return -1;
}

# The landmarks `build` generates when the book has none: the cover page
# when a chapter is one, and the start of the body, the first linear XHTML
# chapter that is not the cover page. No `toc` landmark: it would point at
# nav.xhtml, which is not in the spine, and EPUBCheck refuses a landmark
# into a file outside it (RSC-011); putting the nav in the spine would make
# it a chapter of every book read back.
func generatedLandmarks(b as Book) {
    def out as list of Landmark;
    def cover as int init coverPage($b.chapters);
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].href == $b.cover) {
            $cover = $i;
        }
    }
    if ($cover >= 0) {
        $out[] = Landmark{type: "cover", title: "Cover", href: $b.chapters[$cover].href};
    }
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].linear and $i != $cover and $b.chapters[$i].mediaType == XHTML_TYPE) {
            $out[] = Landmark{type: "bodymatter", title: "Start", href: $b.chapters[$i].href};
            break;
        }
    }
    return $out;
}

# The hrefs of the chapters, the documents a navigation link may lead to.
func chapterHrefs(b as Book) {
    def out as map of string to bool;
    for (def i in 0..len($b.chapters)) {
        $out[$b.chapters[$i].href] = true;
    }
    return $out;
}

# A hidden `<nav>` of plain links, "" kind for none written: the landmarks
# (each link with its `epub:type`) or the page list. A link into a file
# outside the spine is left out (EPUBCheck RSC-011; `check` reports it).
func linkNav(kind as string, links as list of Landmark, chapters as map of string to bool) {
    def ol as xml.Value init xml.element("ol");
    def n as int init 0;
    for (def l in $links) {
        if (not maps.has($chapters, splitFragment($l.href)[0])) {
            continue;
        }
        def a as xml.Value init xml.element("a");
        if ($l.type != "") {
            $a = xml.setAttr($a, "epub:type", $l.type);
        }
        $a = xml.setAttr($a, "href", hrefUrl($l.href));
        $ol = xml.append($ol, xml.append(xml.element("li"), xml.setText($a, $l.title)));
        $n = $n + 1;
    }
    def nav as xml.Value init xml.setAttr(xml.element("nav"), "epub:type", $kind);
    $nav = xml.setAttr($nav, "id", $kind);
    $nav = xml.setAttr($nav, "hidden", "hidden");
    if ($n == 0) {
        return xml.element("none");
    }
    return xml.append($nav, $ol);
}

# The navigation document: the reader's table of contents, and the one the
# format requires, then the landmarks (the book's, else generated ones) and
# the page list when the book has one.
func navXhtml(b as Book, entries as list of TocEntry) {
    def nav as xml.Value init xml.setAttr(xml.element("nav"), "epub:type", "toc");
    $nav = xml.setAttr($nav, "id", "toc");
    $nav = xml.append($nav, xml.setText(xml.element("h1"), $b.title));
    $nav = xml.append($nav, navList($entries));
    def css as string init "";
    if (hasStylesheet($b)) {
        $css = CSS_HREF;
    }
    def chapters as map of string to bool init chapterHrefs($b);
    def body as xml.Value init xml.append(xml.element("body"), $nav);
    def marks as list of Landmark init $b.landmarks;
    if (len($marks) == 0) {
        $marks = generatedLandmarks($b);
    }
    def more as xml.Value init linkNav("landmarks", $marks, $chapters);
    if (xml.tag($more) != "none") {
        $body = xml.append($body, $more);
    }
    def pages as list of Landmark;
    for (def p in $b.pages) {
        $pages[] = Landmark{type: "", title: $p.label, href: $p.href};
    }
    $more = linkNav("page-list", $pages, $chapters);
    if (xml.tag($more) != "none") {
        $body = xml.append($body, $more);
    }
    return xhtmlPage($b.lang, $b.direction, "", $b.title, $css, $body);
}

# The first target at or under entry `i`: an NCX navPoint must point
# somewhere, so a heading points at its first child.
func firstTarget(entries as list of TocEntry, i as int) {
    def k as int init $i;
    while ($k < len($entries) and ($k == $i or $entries[$k].level > $entries[$i].level)) {
        if ($entries[$k].href != "") {
            return $entries[$k].href;
        }
        $k = $k + 1;
    }
    return "";
}

# The play order of every entry: entries that point at the same target share
# one, as the NCX requires, and a new target takes the next number.
func playOrders(entries as list of TocEntry) {
    def seen as map of string to int;
    def out as list of int;
    for (def i in 0..len($entries)) {
        def target as string init firstTarget($entries, $i);
        if (not maps.has($seen, $target)) {
            $seen[$target] = len($seen) + 1;
        }
        $out[] = $seen[$target];
    }
    return $out;
}

# One navPoint, without its children.
func ncxPoint(entries as list of TocEntry, i as int, orders as list of int) {
    def point as xml.Value init xml.setAttr(
        xml.element("navPoint"),
        "id",
        "np" + convert.toString($i + 1));
    $point = xml.setAttr($point, "playOrder", convert.toString($orders[$i]));
    def label as xml.Value init xml.append(
        xml.element("navLabel"),
        xml.setText(xml.element("text"), $entries[$i].title));
    $point = xml.append($point, $label);
    return xml.append(
        $point,
        xml.setAttr(xml.element("content"), "src", hrefUrl(firstTarget($entries, $i))));
}

# The `<navMap>`: each entry a navPoint, its deeper entries nested in it.
# `orders` is `playOrders` of the entries. An explicit stack of open points,
# one per level, as in `navList`.
func ncxPoints(entries as list of TocEntry, orders as list of int) {
    def navMap as xml.Value init xml.element("navMap");
    def points as list of xml.Value;
    for (def i in 0..len($entries)) {
        def level as int init $entries[$i].level;
        while (len($points) > $level + 1) {
            def k as int init len($points) - 1;
            $points[$k - 1] = xml.append($points[$k - 1], $points[$k]);
            $points = $points[..$k];
        }
        def point as xml.Value init ncxPoint($entries, $i, $orders);
        if (len($points) == $level + 1) {
            if ($level == 0) {
                $navMap = xml.append($navMap, $points[0]);
            } else {
                $points[$level - 1] = xml.append($points[$level - 1], $points[$level]);
            }
            $points[$level] = $point;
        } else {
            $points[] = $point;
        }
    }
    while (len($points) > 1) {
        def k as int init len($points) - 1;
        $points[$k - 1] = xml.append($points[$k - 1], $points[$k]);
        $points = $points[..$k];
    }
    if (len($points) == 1) {
        $navMap = xml.append($navMap, $points[0]);
    }
    return $navMap;
}

func ncxMeta(name as string, content as string) {
    return xml.setAttr(xml.setAttr(xml.element("meta"), "name", $name), "content", $content);
}

# The EPUB 2 table of contents, for readers that do not know `nav.xhtml`.
func tocNcx(b as Book, entries as list of TocEntry) {
    def depth as int init 0;
    for (def e in $entries) {
        if ($e.level + 1 > $depth) {
            $depth = $e.level + 1;
        }
    }
    def head as xml.Value init xml.element("head");
    $head = xml.append($head, ncxMeta("dtb:uid", $b.identifier));
    $head = xml.append($head, ncxMeta("dtb:depth", convert.toString($depth)));
    $head = xml.append($head, ncxMeta("dtb:totalPageCount", "0"));
    $head = xml.append($head, ncxMeta("dtb:maxPageNumber", "0"));
    def out as xml.Value init xml.setAttr(xml.element("ncx"), "xmlns", NCX_NS);
    $out = xml.setAttr($out, "version", "2005-1");
    $out = xml.setAttr($out, "xml:lang", $b.lang);
    $out = xml.append($out, $head);
    $out = xml.append(
        $out,
        xml.append(xml.element("docTitle"), xml.setText(xml.element("text"), $b.title)));
    $out = xml.append($out, ncxPoints($entries, playOrders($entries)));
    return xmlDocument($out);
}

# --- building the book ---------------------------------------------------

# --- a read book, made writable ----------------------------------------------
#
# A book `read` returns can hold what the builders never make: its old
# navigation document in the spine under the name or id `build` gives its
# own (`nav.xhtml`, `nav`), or pictures in the spine (a fixed-layout comic),
# each both a chapter without content and a resource. `forWriting` converts
# those, and is the identity for every other book, so a book the builders
# made is written as it is.

# The first href not yet taken: `stem` + `ext`, else `stem-1` + `ext`, ...
func freeHref(t as Taken, stem as string, ext as string) {
    def k as int init 0;
    def out as string init $stem + $ext;
    while (maps.has($t.hrefs, strings.lower($out))) {
        $k = $k + 1;
        $out = $stem + "-" + convert.toString($k) + $ext;
    }
    return $out;
}

# A path without its extension, and the extension with its dot.
func stemAndExt(href as string) {
    def slash as int init strings.lastIndexOf($href, "/");
    def dot as int init strings.lastIndexOf($href, ".");
    if ($dot <= $slash + 1) {
        return [$href, ""];
    }
    return [$href[..$dot], $href[$dot..]];
}

# The viewport a fixed-layout page uses when its picture's size cannot be
# read (WebP, SVG) and the book sets none: A4 proportions.
def const DEFAULT_VIEWPORT as string init "width=1000, height=1414";

# The width and height of a PNG, GIF or JPEG from its header, [] when the
# format is another or the header is cut short. Read by hand: the `images`
# library is out of reach here, its name being taken by the `images` builder.
func pictureSize(data as bytes) {
    def n as int init len($data);
    if ($n >= 24 and binary.startsWith($data, encoding.fromText("hex", "89504e470d0a1a0a"))) {
        return [binary.readUint("be", $data, 16, 4), binary.readUint("be", $data, 20, 4)];
    }
    if ($n >= 10 and binary.startsWith($data, bytesOf("GIF8"))) {
        return [binary.readUint("le", $data, 6, 2), binary.readUint("le", $data, 8, 2)];
    }
    if ($n < 4 or $data[0] != 0xFF or $data[1] != 0xD8) {
        return [];
    }
    # JPEG: walk the segments to the first start-of-frame (SOF0 to SOF15
    # but DHT, JPG and DAC), which holds the height, then the width.
    def p as int init 2;
    while ($p + 9 <= $n) {
        if ($data[$p] != 0xFF) {
            return [];
        }
        def marker as int init $data[$p + 1];
        if ($marker == 0xFF) {
            $p = $p + 1;
            continue;
        }
        if ($marker >= 0xC0 and $marker <= 0xCF and $marker != 0xC4 and $marker != 0xC8 and
            $marker != 0xCC) {
            return [
                binary.readUint("be", $data, $p + 7, 2),
                binary.readUint("be", $data, $p + 5, 2)
            ];
        }
        if ($marker == 0xD8 or ($marker >= 0xD0 and $marker <= 0xD7) or $marker == 0x01) {
            $p = $p + 2;
            continue;
        }
        $p = $p + 2 + binary.readUint("be", $data, $p + 2, 2);
    }
    return [];
}

# Whether a page is fixed layout: the book's layout, unless its itemref
# overrides it.
func prePaginated(b as Book, c as Chapter) {
    if (hasProperty($c.spineProperties, "rendition:layout-pre-paginated")) {
        return true;
    }
    if (hasProperty($c.spineProperties, "rendition:layout-reflowable")) {
        return false;
    }
    return $b.layout == "pre-paginated";
}

# The XHTML page that shows a picture of the spine, in the picture's
# directory. In a fixed-layout book it carries the viewport a fixed-layout
# page needs: the picture's size, read from its header (`pictureSize`), else
# the book's `viewport`, else DEFAULT_VIEWPORT.
func picturePage(b as Book, c as Chapter, href as string, id as string, data as bytes) {
    def label as string init $c.title;
    if (strings.trim($label) == "") {
        $label = $b.title;
    }
    def name as string init $c.href;
    def slash as int init strings.lastIndexOf($name, "/");
    if ($slash >= 0) {
        $name = $name[$slash + 1..];
    }
    def img as xml.Value init xml.setAttr(xml.element("img"), "src", hrefUrl($name));
    $img = xml.setAttr($img, "alt", $label);
    def viewport as string init "";
    if (prePaginated($b, $c)) {
        $viewport = $b.viewport;
        def size as list of int init pictureSize($data);
        if (len($size) == 2) {
            $viewport = "width=" + convert.toString($size[0]) + ", height=" +
                convert.toString($size[1]);
        }
        if ($viewport == "") {
            $viewport = DEFAULT_VIEWPORT;
        }
        $img = xml.setAttr($img, "style", "display: block; width: 100%; height: 100%;");
    }
    return Chapter{
        id: $id,
        href: $href,
        title: $c.title,
        mediaType: XHTML_TYPE,
        properties: "",
        content: xhtmlPage(
            $b.lang,
            $b.direction,
            $viewport,
            $label,
            "",
            xml.append(xml.setAttr(xml.element("body"), "style", "margin: 0;"), $img)),
        linear: $c.linear,
        wellFormed: true,
        spineProperties: $c.spineProperties,
        mediaOverlay: ""
    };
}

func forWriting(b as Book) {
    def out as Book init $b;
    # The book's own navigation document, kept by `read` as a file because
    # chapters link into it, becomes a chapter out of the reading order, so
    # those links lead to a document in the spine (EPUBCheck RSC-011).
    def kept as list of Resource;
    for (def i in 0..len($b.resources)) {
        def r as Resource init $b.resources[$i];
        if (hasProperty($r.properties, "nav") and strings.lower($r.mediaType) == XHTML_TYPE) {
            def text as string init "";
            try {
                $text = convert.stringFromBytes("utf-8", $r.data);
            } catch (e) {
                $kept[] = $r;
                continue;
            }
            $out.chapters[] = Chapter{
                id: $r.id,
                href: $r.href,
                title: "",
                mediaType: XHTML_TYPE,
                properties: withoutProperty($r.properties, "nav"),
                content: $text,
                linear: false,
                wellFormed: wellFormedXml($text),
                spineProperties: "",
                mediaOverlay: ""
            };
            $out.notes[] = "the book's own navigation document " + shown($r.href) +
                " is written as a chapter out of the reading order, since chapters link into it";
            continue;
        }
        $kept[] = $r;
    }
    $out.resources = $kept;
    def t as Taken init takenOf($out);
    def moved as map of string to string;
    def renames as list of list of string;
    for (def i in 0..len($out.chapters)) {
        def c as Chapter init $out.chapters[$i];
        if (not isDocument($c.mediaType)) {
            def at as int init resourceAt($out, $c.href);
            if ($at < 0) {
                fail("input", "spine picture " + shown($c.href) + " is not a file of the book");
            }
            def href as string init freeHref($t, stemAndExt($c.href)[0], ".xhtml");
            def id as string init $c.id + "-page";
            if (maps.has($t.ids, $id)) {
                $id = freeId($t, $id, 1);
            }
            $t.hrefs[strings.lower($href)] = true;
            $t.ids[$id] = true;
            $out.chapters[$i] = picturePage($out, $c, $href, $id, $out.resources[$at].data);
            $moved[$c.href] = $href;
            $out.notes[] = "the picture " + shown($c.href) + " in the spine is shown by the page " +
                shown($href);
            continue;
        }
        def legacy as Html5 init html5Page($c.content);
        if ($legacy.changed) {
            $out.chapters[$i].content = $legacy.content;
            $out.notes[] = "chapter " + shown($c.href) + " is XHTML 1.1; written as HTML5" +
                $legacy.dropped;
        }
        def low as string init strings.lower($c.href);
        if ($low == NAV_HREF or $low == NCX_HREF or $low == OPF_HREF) {
            def parts as list of string init stemAndExt($c.href);
            def href as string init freeHref($t, $parts[0] + "-old", $parts[1]);
            $t.hrefs[strings.lower($href)] = true;
            $renames[] = [$c.href, $href];
        }
        if (lists.contains(RESERVED_IDS, $c.id)) {
            def id as string init freeId($t, $c.id + "-old", 1);
            $t.ids[$id] = true;
            $out.chapters[$i].id = $id;
        }
    }
    if (len($moved) > 0) {
        for (def i in 0..len($out.toc)) {
            def path as string init splitFragment($out.toc[$i].href)[0];
            if (maps.has($moved, $path)) {
                $out.toc[$i].href = $moved[$path];
            }
        }
        for (def i in 0..len($out.landmarks)) {
            def path as string init splitFragment($out.landmarks[$i].href)[0];
            if (maps.has($moved, $path)) {
                $out.landmarks[$i].href = $moved[$path];
            }
        }
        for (def i in 0..len($out.pages)) {
            def path as string init splitFragment($out.pages[$i].href)[0];
            if (maps.has($moved, $path)) {
                $out.pages[$i].href = $moved[$path];
            }
        }
    }
    # A document under the name of one `build` writes itself is renamed, and
    # what links to it follows.
    for (def r in $renames) {
        $out = rename($out, $r[0], $r[1]);
        $out.notes[] = "chapter " + shown($r[0]) + " is written as " + shown($r[1]) +
            ", since build writes its own " + shown(strings.lower($r[0]));
    }
    return $out;
}

func wellFormedXml(text as string) {
    try {
        xml.decode($text);
    } catch (e) {
        if ($e.kind == "limit") {
            throw $e;
        }
        return false;
    }
    return true;
}

# An XHTML 1.1 (or other pre-HTML5) page made an HTML5 one: the HTML5
# doctype, and without what HTML5 forbids that EPUB 2 books carry: the
# `<meta http-equiv>` of Content-Type, Content-Style-Type and
# Content-Script-Type, and a table's `summary`. The text and the rest of the
# markup stay as they are.
def struct Html5 {
    changed as bool,
    content as string,
    dropped as string
};

def const DOCTYPE as string init '(?is)<!DOCTYPE\s[^>\[]*(?:\[[^\]]*\])?\s*>';
def const HTTP_EQUIV as string init '(?is)<meta\s[^>]*http-equiv\s*=\s*["' + "']?" +
    '(?:content-type|content-style-type|content-script-type)[^>]*>';
def const SUMMARY_ATTR as string init '(?is)(<table\b[^>]*?)\s+summary\s*=\s*(?:"[^"]*"|' +
    "'[^']*')";

func html5Page(content as string) {
    def out as Html5 init Html5{changed: false, content: $content, dropped: ""};
    def m as regex.Match init regex.find(DOCTYPE, $content);
    if ($m.start < 0 or strings.lower(regex.replace('\s+', $m.text, " ")) == "<!doctype html>") {
        return $out;
    }
    def page as string init regex.replace(DOCTYPE, $content, "<!DOCTYPE html>");
    def metas as int init len(regex.findAll(HTTP_EQUIV, $page));
    def summaries as int init len(regex.findAll(SUMMARY_ATTR, $page));
    $page = regex.replace(HTTP_EQUIV, $page, "");
    $page = regex.replace(SUMMARY_ATTR, $page, "${1}");
    def dropped as list of string;
    if ($metas > 0) {
        $dropped[] = convert.toString($metas) + " <meta http-equiv>";
    }
    if ($summaries > 0) {
        $dropped[] = convert.toString($summaries) + " table summary";
    }
    $out.changed = true;
    $out.content = $page;
    if (len($dropped) > 0) {
        $out.dropped = ", dropping " + strings.join($dropped, " and ");
    }
    return $out;
}

# A table of contents without the headings that group nothing (an `href`
# `""` with no entry under it), and the notes that say which.
def struct TocDropped {
    entries as list of TocEntry,
    notes as list of string
};

func withoutEmptyHeadings(entries as list of TocEntry) {
    def out as TocDropped init TocDropped{entries: $entries, notes: []};
    def i as int init len($out.entries) - 1;
    while ($i >= 0) {
        def e as TocEntry init $out.entries[$i];
        if ($e.href == "" and
            ($i + 1 >= len($out.entries) or $out.entries[$i + 1].level <= $e.level)) {
            $out.entries = lists.concat($out.entries[..$i], $out.entries[$i + 1..]);
            $out.notes[] = "table of contents heading " + shown($e.title) +
                " has nothing under it; left out";
        }
        $i = $i - 1;
    }
    return $out;
}

/**
 * A book as `build` writes it, with every conversion noted: a read book
 * may hold what the builders never make, and this is where it is made
 * writable. `build` applies the same conversions itself, all but the last:
 * its own navigation document in the spine is renamed when it takes a name
 * `build` writes; its own navigation document kept as a file (chapters link
 * into it) becomes a chapter out of the reading order; a picture in the
 * spine is shown by a generated page; an XHTML 1.1 chapter is written as
 * HTML5, without the `<meta http-equiv>` and table `summary` HTML5 forbids.
 * And here only: a table of contents heading with nothing under it is left
 * out (`build` refuses one, which keeps a builder's mistake visible). Each
 * conversion appends a line to `notes`. For a book the builders made,
 * nothing changes.
 *
 * @param b {Book} the book, typically from `read`
 * @return {Book} the book `build` writes, its notes extended
 * @throws {EpubError} reason "input" for a picture in the spine that is
 *   not a file of the book
 * @example
 *   def b as epub.Book init epub.writable(epub.read($data));
 *   for (def n in $b.notes) {
 *       io.eprintf("note: %s\n", $n);
 *   }
 *   fs.writeBytes("again.epub", epub.build($b));
 */
export func writable(b as Book) {
    def out as Book init forWriting($b);
    def toc as TocDropped init withoutEmptyHeadings($out.toc);
    $out.toc = $toc.entries;
    $out.notes = lists.concat($out.notes, $toc.notes);
    return $out;
}

# The index of the resource at exactly this href, -1 for none.
func resourceAt(b as Book, href as string) {
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href == $href) {
            return $i;
        }
    }
    return -1;
}

# A rendition field is "" or one of its values.
func checkChoice(field as string, value as string, allowed as list of string) {
    if ($value != "" and not lists.contains($allowed, $value)) {
        fail(
            "input",
            $field + " " + shown($value) + ' is not "" or one of ' + strings.join($allowed, ", "));
    }
}

# Everything `build` refuses before it writes a byte.
func checkBook(b as Book) {
    if (strings.trim($b.title) == "") {
        fail("input", "a book needs a title");
    }
    if (strings.trim($b.lang) == "") {
        fail("input", "a book needs a language");
    }
    if (strings.trim($b.identifier) == "") {
        fail("input", "a book needs an identifier");
    }
    if ($b.date != "" and not regex.matches(DATE_SHAPE, $b.date)) {
        fail(
            "input",
            "date " + shown($b.date) + " is not a W3C date (YYYY, YYYY-MM, YYYY-MM-DD, " +
                "or YYYY-MM-DDThh:mm[:ss]TZD); fix it, or clear it with $b.date = \"\"");
    }
    if ($b.modified != "" and not regex.matches(MODIFIED_SHAPE, $b.modified)) {
        fail("input", "modified " + shown($b.modified) + " is not YYYY-MM-DDThh:mm:ssZ");
    }
    if (len($b.chapters) == 0) {
        fail("input", "a book needs at least one chapter");
    }
    checkChoice("layout", $b.layout, ["reflowable", "pre-paginated"]);
    checkChoice("orientation", $b.orientation, ["auto", "landscape", "portrait"]);
    checkChoice("spread", $b.spread, ["none", "landscape", "portrait", "both", "auto"]);
    checkChoice("flow", $b.flow, ["paginated", "scrolled-continuous", "scrolled-doc", "auto"]);
    if ($b.direction != "" and $b.direction != "ltr" and $b.direction != "rtl") {
        fail("input", "direction " + shown($b.direction) + ' is not "", "ltr" or "rtl"');
    }
    def hrefs as map of string to bool init {NAV_HREF: true, OPF_HREF: true};
    if ($b.ncx) {
        $hrefs[NCX_HREF] = true;
    }
    def ids as map of string to bool;
    for (def id in RESERVED_IDS) {
        $ids[$id] = true;
    }
    for (def c in $b.chapters) {
        checkHref($c.href, "chapter");
        if (maps.has($hrefs, strings.lower($c.href))) {
            fail("input", "href " + shown($c.href) + " is used twice");
        }
        $hrefs[strings.lower($c.href)] = true;
        if (not regex.matches(ID_SHAPE, $c.id) or maps.has($ids, $c.id)) {
            fail("input", "chapter id " + shown($c.id) + " is not a free XML name");
        }
        $ids[$c.id] = true;
    }
    def coverFound as bool init $b.cover == "" or maps.has(chapterHrefs($b), $b.cover);
    def overlays as map of string to bool;
    for (def r in $b.resources) {
        if (strings.lower($r.mediaType) == "application/smil+xml") {
            $overlays[$r.id] = true;
        }
        checkHref($r.href, "file");
        if (maps.has($hrefs, strings.lower($r.href))) {
            fail("input", "href " + shown($r.href) + " is used twice");
        }
        $hrefs[strings.lower($r.href)] = true;
        if (not regex.matches(ID_SHAPE, $r.id) or maps.has($ids, $r.id)) {
            fail("input", "file id " + shown($r.id) + " is not a free XML name");
        }
        $ids[$r.id] = true;
        if ($r.href == $b.cover) {
            if (not isImage($r.mediaType)) {
                fail("input", "cover " + shown($r.href) + " is not an image");
            }
            $coverFound = true;
        }
    }
    if (not $coverFound) {
        fail("input", "cover " + shown($b.cover) + " is not a file or a chapter of the book");
    }
    for (def c in $b.chapters) {
        if ($c.mediaOverlay != "" and not maps.has($overlays, $c.mediaOverlay)) {
            fail(
                "input",
                "chapter " + shown($c.href) + "'s media overlay " + shown($c.mediaOverlay) +
                    " is not a SMIL file of the book");
        }
    }
}

/**
 * The book as an EPUB 3.3 file: `mimetype` first and stored, then
 * `META-INF/container.xml`, the package document, the navigation document,
 * `toc.ncx` when `ncx` is set, the chapters and the other files, all under
 * `OEBPS/`. Nothing is read from a clock, so the same book gives the same
 * bytes. Hrefs are written percent-encoded in the package, the navigation
 * document and the NCX. A book from `read` with its navigation document in
 * the spine under the deck's own name, or with pictures in the spine, is
 * converted as it is written (see the guide); `notes` is ignored.
 *
 * @param b {Book} the book
 * @return {bytes} the EPUB file
 * @throws {EpubError} reason "input" for a book without chapters, a used
 *   href or id, a `date` that is not a W3C date, a bad `direction`, or a
 *   cover that is not one of its images; "toc" for a table
 *   of contents that does not nest or points outside the chapters
 * @throws {Error} kind "limit" for a book too large for a zip without zip64,
 *   or a table of contents nested deeper than 100 levels
 * @example
 *   fs.writeBytes("notes.epub", epub.build($b));
 */
export func build(b as Book) {
    def w as Book init forWriting($b);
    checkBook($w);
    def entries as list of TocEntry init tocOf($w);
    checkToc($entries, $w.chapters);
    def files as list of File init [File{name: "mimetype", data: bytesOf(MIMETYPE)}];
    $files[] = File{name: "META-INF/container.xml", data: bytesOf(containerXml())};
    $files[] = File{name: "OEBPS/" + OPF_HREF, data: bytesOf(contentOpf($w))};
    $files[] = File{name: "OEBPS/" + NAV_HREF, data: bytesOf(navXhtml($w, $entries))};
    if ($w.ncx) {
        $files[] = File{name: "OEBPS/" + NCX_HREF, data: bytesOf(tocNcx($w, $entries))};
    }
    for (def i in 0..len($w.chapters)) {
        $files[] = File{
            name: "OEBPS/" + $w.chapters[$i].href,
            data: bytesOf($w.chapters[$i].content)
        };
    }
    for (def i in 0..len($w.resources)) {
        $files[] = File{name: "OEBPS/" + $w.resources[$i].href, data: $w.resources[$i].data};
    }
    return zipOf($files, $w.compress);
}
