# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# epub - white-box tests for the core topic, and the helpers the other
# overlays use. Spliced into epub_test.j via include - run with:
#   jennifer test src/epub_test.j

func textOf(data as bytes) {
    return encoding.decode("utf-8", $data);
}

# The reason of the EpubError `read` throws for these bytes, or the kind of
# any other error, or "" when it reads.
func readReason(data as bytes) {
    try {
        readWith($data, readOptions());
    } catch (e) {
        if ($e.kind == ERROR_KIND) {
            return $e.reason;
        }
        return "kind:" + $e.kind;
    }
    return "";
}

# The same for `build`.
func buildReason(b as Book) {
    try {
        build($b);
    } catch (e) {
        if ($e.kind == ERROR_KIND) {
            return $e.reason;
        }
        return "kind:" + $e.kind;
    }
    return "";
}

# A container document pointing at `opf`.
func containerFor(opf as string) {
    return '<?xml version="1.0"?><container version="1.0" ' +
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>' +
        '<rootfile full-path="' + $opf + '" media-type="application/oebps-package+xml"/>' +
        '</rootfiles></container>';
}

# A package document with one XHTML chapter, `ch.xhtml`, and `extra`
# spliced into the manifest.
func opfWith(metadata as string, extra as string) {
    return '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" ' +
        'unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' +
        $metadata + '</metadata><manifest>' +
        '<item id="c1" href="ch.xhtml" media-type="application/xhtml+xml"/>' + $extra +
        '</manifest><spine><itemref idref="c1"/></spine></package>';
}

def const META as string init '<dc:identifier id="uid">urn:x:1</dc:identifier>' +
    '<dc:title>T</dc:title><dc:language>en</dc:language>';

def const PAGE as string init '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">' +
    '<head><title>Page</title></head><body><p>Hello.</p></body></html>';

# A hand-made book: `mimetype` first and stored, then the files given.
func handMade(files as list of File) {
    def all as list of File init [File{name: "mimetype", data: bytesOf(MIMETYPE)}];
    for (def f in $files) {
        $all[] = $f;
    }
    return zipOf($all, false);
}

# The smallest valid book, with a chapter of our choosing and extra files.
func minimalBook(chapter as string, extra as list of File) {
    def files as list of File init [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))},
        File{name: "OPS/ch.xhtml", data: bytesOf($chapter)}
    ];
    for (def f in $extra) {
        $files[] = $f;
    }
    return handMade($files);
}

func testPathsAreCleanedAndJoinedWithSlashes() {
    testing.assertEqual(cleanPath("a/./b//c"), "a/b/c");
    testing.assertEqual(cleanPath("a/b/../c"), "a/c");
    testing.assertEqual(cleanPath("../x"), "../x");
    testing.assertEqual(cleanPath("a/../../x"), "../x");
    testing.assertEqual(joinPath("OEBPS", "text/a.xhtml"), "OEBPS/text/a.xhtml");
    testing.assertEqual(joinPath("OEBPS/text", "../img/a.png"), "OEBPS/img/a.png");
    testing.assertEqual(joinPath("", "a.xhtml"), "a.xhtml");
    testing.assertEqual(dirOf("a/b/c.xhtml"), "a/b");
    testing.assertEqual(dirOf("c.xhtml"), "");
    testing.assertEqual(splitFragment("a.xhtml#x"), ["a.xhtml", "#x"]);
    testing.assertEqual(splitFragment("a.xhtml"), ["a.xhtml", ""]);
}

func testMediaTypesComeFromTheExtension() {
    testing.assertEqual(mediaOf("img/logo.PNG"), "image/png");
    testing.assertEqual(mediaOf("photo.jpeg"), "image/jpeg");
    testing.assertEqual(mediaOf("fonts/a.woff2"), "font/woff2");
    testing.assertEqual(mediaOf("a.b/README"), "");
    testing.assertEqual(mediaOf("notes.xyz"), "");
    testing.assertTrue(isImage("image/svg+xml"));
    testing.assertFalse(isImage("text/css"));
}

func testPropertiesAreSpaceSeparated() {
    testing.assertTrue(hasProperty("svg cover-image", "cover-image"));
    testing.assertFalse(hasProperty("cover-images", "cover-image"));
    testing.assertFalse(hasProperty("", "nav"));
}

# Hrefs may hold any Unicode letter; they are refused for what climbs out of
# the book, what OCF forbids in a file name, and a space, which EPUBCheck
# warns about (PKG-010). Before, "a b.xhtml" was accepted.
func testHrefsTheWriterAccepts() {
    checkHref("ch01.xhtml", "chapter");
    checkHref("text/part-1/a_b.xhtml", "chapter");
    checkHref("kapitel/übung.xhtml", "chapter");
    checkHref("日本/一.xhtml", "chapter");
    checkHref(".hidden", "file");
    checkHref("100%.xhtml", "chapter");
    for (def bad in [
        "",
        "/abs.xhtml",
        "../up.xhtml",
        "a/../b.xhtml",
        "./a.xhtml",
        "a//b",
        "a:b.xhtml",
        "https://x.org/a.xhtml",
        "a?.xhtml",
        "a#b.xhtml",
        "a\\b.xhtml",
        "tab\t.xhtml",
        "end.",
        "a b.xhtml",
        "dir name/a.xhtml"
    ]) {
        def got as string init "";
        try {
            checkHref($bad, "chapter");
        } catch (e) {
            $got = $e.reason;
        }
        testing.assertEqual($got, "input");
    }
}

func testTheErrorIsAStructWithAReason() {
    def caught as bool init false;
    try {
        fail("drm", "locked");
    } catch (e) {
        testing.assertEqual($e.kind, "epub");
        testing.assertEqual($e.message, "epub: locked");
        testing.assertEqual($e.reason, "drm");
        $caught = true;
    }
    testing.assertTrue($caught);
}

func testLongNamesAreShortenedInMessages() {
    testing.assertEqual(shown("a"), '"a"');
    testing.assertEqual(len(shown(strings.replicate("x", 500))), 125);
}

# Hrefs are written percent-encoded wherever they are URLs; a plain ASCII
# href is unchanged, so books with such names keep their bytes.
func testHrefsAreWrittenPercentEncoded() {
    testing.assertEqual(hrefUrl("text/ch-1_a.xhtml#x"), "text/ch-1_a.xhtml#x");
    testing.assertEqual(hrefUrl("a b/übung.xhtml#sec"), "a%20b/%C3%BCbung.xhtml#sec");
    testing.assertEqual(hrefUrl("100%.xhtml"), "100%25.xhtml");
}
