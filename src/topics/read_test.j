# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# epub - white-box tests for reading: round trips, the Project Gutenberg
# fixtures, hand-made books for every refusal, DRM, caps and font
# obfuscation. Spliced into epub_test.j via include.

# The Project Gutenberg books live in testdata/gutenberg/
# (tools/build-fixtures.sh), outside src/, so a consumer never vendors them.
# Where testdata/ is missing (jvc publish and jvc install --runtests run the
# overlays from a copy of src/ alone), the tests that read them return early;
# tools/check-extra.sh fails the gate if the files are gone.
func haveGutenberg() {
    return fs.isFile("testdata/gutenberg/pg1080-epub3.epub") and
        fs.isFile("testdata/gutenberg/pg1080-epub2.epub");
}

func gutenberg3() {
    return read(fs.readBytes("testdata/gutenberg/pg1080-epub3.epub"));
}

func gutenberg2() {
    return read(fs.readBytes("testdata/gutenberg/pg1080-epub2.epub"));
}

# --- round trips -----------------------------------------------------------

func richBook() {
    def b as Book init sampleBook();
    $b = author($b, "Grace");
    $b.description = "About & such";
    $b.publisher = "Pub";
    $b.date = "2026-11-14";
    $b = cover($b, "img/cover.png", bytesOf("PNGDATA"));
    $b = file($b, "fonts/a.woff2", "font/woff2", bytesOf("FONT"));
    $b = tocEntry($b, "Intro", "intro.xhtml", 0);
    $b = tocEntry($b, "Part", "", 0);
    $b = tocEntry($b, "Two", "text/two.xhtml", 1);
    $b = tocEntry($b, "Deep", "text/two.xhtml#t", 2);
    $b.chapters[1].linear = false;
    $b.ncx = true;
    return $b;
}

func testABuiltBookReadsBackAsItWasWritten() {
    def b as Book init richBook();
    def back as Book init read(build($b));
    testing.assertEqual($back.title, $b.title);
    testing.assertEqual($back.lang, "en");
    testing.assertEqual($back.identifier, $b.identifier);
    testing.assertEqual($back.authors, ["Ada", "Grace"]);
    testing.assertEqual($back.description, "About & such");
    testing.assertEqual($back.publisher, "Pub");
    testing.assertEqual($back.date, "2026-11-14");
    testing.assertEqual($back.modified, FIXED_MODIFIED);
    testing.assertEqual($back.version, "3.0");
    testing.assertEqual($back.cover, "img/cover.png");
    testing.assertTrue($back.ncx);
    testing.assertEqual($back.chapters, $b.chapters);
    testing.assertEqual($back.toc, $b.toc);
    testing.assertEqual($back.resources, $b.resources);
}

# Reading a built book and building it again gives the same bytes: the
# reader keeps everything the writer needs.
func testReadAndBuildIsAFixedPoint() {
    def once as bytes init build(richBook());
    testing.assertEqual(digestOf(build(read($once))), digestOf($once));
    def plain as bytes init build(sampleBook());
    testing.assertEqual(digestOf(build(read($plain))), digestOf($plain));
}

func testWithoutAnExplicitTableOfContentsTheChaptersAreListed() {
    def back as Book init read(build(sampleBook()));
    testing.assertEqual(
        $back.toc,
        [
            TocEntry{title: "Intro", href: "intro.xhtml", level: 0},
            TocEntry{title: "Two", href: "text/two.xhtml", level: 0}
        ]);
    testing.assertFalse($back.ncx);
    testing.assertEqual($back.cover, "");
}

# --- real-world books ------------------------------------------------------

def const SWIFT_TITLE as string init "A Modest Proposal / For preventing the children of poor " +
    "people in Ireland, from being a burden on their parents or country, and for making them " +
    "beneficial to the publick";

func testAGutenbergEpub3IsRead() {
    if (not haveGutenberg()) {
        return;
    }
    def b as Book init gutenberg3();
    testing.assertEqual($b.version, "3.0");
    testing.assertEqual($b.title, SWIFT_TITLE);
    testing.assertEqual($b.lang, "en");
    testing.assertEqual($b.identifier, "http://www.gutenberg.org/1080");
    testing.assertEqual($b.authors, ["Jonathan Swift"]);
    testing.assertEqual($b.date, "1997-10-01");
    testing.assertEqual($b.modified, "2026-10-01T12:29:22Z");
    testing.assertEqual($b.cover, "4801362310348186356_cover.jpg");
    testing.assertTrue($b.ncx);
    testing.assertEqual(len($b.chapters), 4);
    testing.assertEqual($b.chapters[0].href, "wrap0000.xhtml");
    testing.assertEqual($b.chapters[0].properties, "svg");
    testing.assertEqual($b.chapters[2].id, "item4");
    testing.assertTrue($b.chapters[2].wellFormed);
    testing.assertEqual($b.chapters[3].title, "THE FULL PROJECT GUTENBERG\u2122 LICENSE");
    # The EPUB 3 navigation document wins over the NCX.
    testing.assertEqual(len($b.toc), 4);
    testing.assertEqual(
        $b.toc[2],
        TocEntry{
            title: "1729",
            href: "6893508861643006172_1080-h-0.htm.xhtml#pgepubid00002",
            level: 0
        });
    testing.assertEqual(len($b.resources), 4);
    def jpeg as Resource init resource($b, $b.cover);
    testing.assertEqual($jpeg.mediaType, "image/jpeg");
    testing.assertEqual($jpeg.properties, "cover-image");
    testing.assertTrue(binary.startsWith($jpeg.data, encoding.fromText("hex", "ffd8")));
    testing.assertContains(
        text($b.chapters[2]),
        "It is a melancholy object to those, who walk through this great town");
}

func testAGutenbergEpub2IsRead() {
    if (not haveGutenberg()) {
        return;
    }
    def b as Book init gutenberg2();
    testing.assertEqual($b.version, "2.0");
    testing.assertEqual($b.title, SWIFT_TITLE);
    testing.assertEqual($b.modified, "");
    # No `cover-image` property in EPUB 2: the cover comes from the meta.
    testing.assertEqual($b.cover, "4801362310348186356_cover.jpg");
    testing.assertEqual(len($b.chapters), 3);
    testing.assertEqual($b.chapters[1].href, "6893508861643006172_1080-h-0.htm.html");
    # The table of contents comes from toc.ncx.
    testing.assertTrue($b.ncx);
    testing.assertEqual(len($b.toc), 4);
    testing.assertEqual($b.toc[3].href, "6893508861643006172_1080-h-1.htm.html#pg-footer-heading");
    testing.assertEqual(len($b.resources), 3);
    testing.assertContains(text($b.chapters[2]), "a young healthy child well nursed");
}

# A real book rebuilt as EPUB 3 keeps its text.
func testAGutenbergBookSurvivesARebuild() {
    if (not haveGutenberg()) {
        return;
    }
    def b as Book init gutenberg3();
    def again as Book init read(build($b));
    testing.assertEqual($again.chapters, $b.chapters);
    testing.assertEqual($again.toc, $b.toc);
    testing.assertEqual($again.resources, $b.resources);
    testing.assertEqual($again.cover, $b.cover);
}

# --- strict container and package -------------------------------------------

func testWhatIsNotAnEpubIsRefused() {
    testing.assertEqual(
        readReason(bytesOf("not a zip at all, but long enough to look")),
        "archive");
    testing.assertEqual(readReason(bytesOf("")), "archive");
    # A zip whose first entry is not mimetype.
    def noMime as bytes init zipOf(
        [
            File{name: "META-INF/container.xml", data: bytesOf(containerFor("a.opf"))}
        ],
        false);
    testing.assertEqual(readReason($noMime), "container");
    def wrongMime as bytes init zipOf(
        [File{name: "mimetype", data: bytesOf("application/zip")}],
        false);
    testing.assertEqual(readReason($wrongMime), "container");
    # A mimetype written with deflate (method 8) by `archive.pack`.
    def packed as bytes init archive.pack(
        "zip",
        [archive.Entry{name: "mimetype", data: bytesOf(MIMETYPE), mode: 0, mtime: 0}]);
    if ($packed[8] == 8) {
        testing.assertEqual(readReason($packed), "container");
    }
    # A truncated archive.
    def whole as bytes init build(sampleBook());
    testing.assertEqual(readReason($whole[..len($whole) - 30]), "archive");
}

func testTheContainerIsReadStrictly() {
    def opf as File init File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))};
    def page as File init File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)};
    testing.assertEqual(readReason(handMade([$opf, $page])), "container");
    def broken as File init File{name: "META-INF/container.xml", data: bytesOf("<container>")};
    testing.assertEqual(readReason(handMade([$broken, $opf, $page])), "container");
    def foreign as File init File{name: "META-INF/container.xml", data: bytesOf("<container/>")};
    testing.assertEqual(readReason(handMade([$foreign, $opf, $page])), "container");
    def noRoot as File init File{
        name: "META-INF/container.xml",
        data: bytesOf('<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles/></container>')
    };
    testing.assertEqual(readReason(handMade([$noRoot, $opf, $page])), "container");
    def outside as File init File{
        name: "META-INF/container.xml",
        data: bytesOf(containerFor("../x.opf"))
    };
    testing.assertEqual(readReason(handMade([$outside, $opf, $page])), "container");
    def missing as File init File{
        name: "META-INF/container.xml",
        data: bytesOf(containerFor("OPS/none.opf"))
    };
    testing.assertEqual(readReason(handMade([$missing, $opf, $page])), "package");
    testing.assertEqual(readReason(minimalBook(PAGE, [])), "");
}

# The book with this package document and the usual chapter.
func withOpf(opf as string) {
    return handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)}
    ]);
}

func testThePackageIsReadStrictly() {
    def id as string init '<dc:identifier id="uid">urn:x:1</dc:identifier>';
    def t as string init "<dc:title>T</dc:title>";
    def l as string init "<dc:language>en</dc:language>";
    testing.assertEqual(readReason(withOpf(opfWith($id + $t + $l, ""))), "");
    testing.assertEqual(readReason(withOpf(opfWith($t + $l, ""))), "package");
    testing.assertEqual(readReason(withOpf(opfWith($id + $l, ""))), "package");
    testing.assertEqual(
        readReason(withOpf(opfWith($id + "<dc:title> </dc:title>" + $l, ""))),
        "package");
    testing.assertEqual(readReason(withOpf(opfWith($id + $t, ""))), "package");
    def other as string init '<dc:identifier id="other">urn:x:1</dc:identifier>';
    testing.assertEqual(readReason(withOpf(opfWith($other + $t + $l, ""))), "package");
    testing.assertEqual(readReason(withOpf("<package>")), "package");
    testing.assertEqual(readReason(withOpf("<package/>")), "package");
    testing.assertEqual(
        readReason(withOpf(opfWith(META, '<item id="c1" href="x.png" media-type="image/png"/>'))),
        "package");
    testing.assertEqual(
        readReason(withOpf(opfWith(
            META,
            '<item id="x" href="../../x.png" media-type="image/png"/>'))),
        "package");
    testing.assertEqual(
        readReason(withOpf(opfWith(META, '<item id="x" media-type="image/png"/>'))),
        "package");
    def noSpine as string init strings.replace(
        opfWith(META, ""),
        '<spine><itemref idref="c1"/></spine>',
        "");
    testing.assertEqual(readReason(withOpf($noSpine)), "package");
    def emptySpine as string init strings.replace(opfWith(META, ""), '<itemref idref="c1"/>', "");
    testing.assertEqual(readReason(withOpf($emptySpine)), "package");
    def badRef as string init strings.replace(opfWith(META, ""), 'idref="c1"', 'idref="c9"');
    testing.assertEqual(readReason(withOpf($badRef)), "package");
    def badToc as string init strings.replace(opfWith(META, ""), "<spine>", '<spine toc="nope">');
    testing.assertEqual(readReason(withOpf($badToc)), "package");
}

# A remote resource is legal in EPUB 3 and has no bytes in the archive: it is
# left out, not refused.
func testARemoteResourceIsLeftOut() {
    def b as Book init read(withOpf(opfWith(
        META,
        '<item id="r" href="https://example.org/a.mp3" media-type="audio/mpeg"/>')));
    testing.assertEqual(len($b.resources), 0);
    testing.assertEqual(len($b.chapters), 1);
}

func testPercentEscapedHrefsNameTheirFiles() {
    def opf as string init strings.replace(
        opfWith(META, '<item id="p" href="my%20pic.png" media-type="image/png"/>'),
        'href="ch.xhtml"',
        'href="c%68.xhtml"');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/my pic.png", data: bytesOf("P")}
    ]));
    testing.assertEqual($b.chapters[0].href, "ch.xhtml");
    testing.assertEqual($b.resources[0].href, "my pic.png");
    testing.assertEqual(textOf(resource($b, "my pic.png").data), "P");
}

# A picture in the spine (a fixed-layout book) is a chapter with no text; its
# bytes are a resource.
func testAForeignSpineItemIsAChapterWithoutText() {
    def opf as string init strings.replace(
        opfWith(META, '<item id="p" href="p.jpg" media-type="image/jpeg"/>'),
        '<itemref idref="c1"/>',
        '<itemref idref="c1"/><itemref idref="p"/>');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/p.jpg", data: encoding.fromText("hex", "ffd8ffd9")}
    ]));
    testing.assertEqual(len($b.chapters), 2);
    testing.assertEqual($b.chapters[1].mediaType, "image/jpeg");
    testing.assertEqual($b.chapters[1].content, "");
    testing.assertEqual(text($b.chapters[1]), "");
    testing.assertEqual(len(resource($b, "p.jpg").data), 4);
}

func testAChapterThatIsNotUtf8IsRefused() {
    def latin1 as bytes init encoding.fromText("hex", "3c703ee93c2f703e");
    testing.assertEqual(readReason(minimalBook(textOf(bytesOf("")), [])), "");
    def b as bytes init handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))},
        File{name: "OPS/ch.xhtml", data: $latin1}
    ]);
    testing.assertEqual(readReason($b), "content");
}

func testAByteOrderMarkIsDropped() {
    def b as Book init read(minimalBook("\uFEFF" + PAGE, []));
    testing.assertTrue(strings.startsWith($b.chapters[0].content, "<?xml"));
    testing.assertTrue($b.chapters[0].wellFormed);
    testing.assertEqual($b.chapters[0].title, "Page");
}

# UTF-16 with its byte order mark, either order, is the other encoding XML
# and EPUB allow, for the package document as for a chapter. A character
# outside the BMP is a surrogate pair. Without the mark it is not UTF-16.
func utf16(text as string, order as string) {
    def out as bytes init encoding.fromText("hex", "feff");
    if ($order == "le") {
        $out = encoding.fromText("hex", "fffe");
    }
    for (def ch in strings.chars($text)) {
        def n as int init convert.toCodepoint($ch);
        def units as list of int init [$n];
        if ($n > 0xFFFF) {
            $units = [0xD800 + (($n - 0x10000) >> 10), 0xDC00 + (($n - 0x10000) & 0x3FF)];
        }
        for (def u in $units) {
            if ($order == "le") {
                $out[] = $u & 0xFF;
                $out[] = $u >> 8;
            } else {
                $out[] = $u >> 8;
                $out[] = $u & 0xFF;
            }
        }
    }
    return $out;
}

func testUtf16DocumentsAreRead() {
    def page as string init '<?xml version="1.0" encoding="UTF-16"?><html xmlns="http://www.w3.org/1999/xhtml">' +
        "<head><title>P\u00e4ge \U0001D11E</title></head><body><p>Caf\u00e9</p></body></html>";
    for (def order in ["le", "be"]) {
        def b as Book init read(handMade([
            File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
            File{name: "OPS/package.opf", data: utf16(opfWith(META, ""), $order)},
            File{name: "OPS/ch.xhtml", data: utf16($page, $order)}
        ]));
        testing.assertEqual($b.title, "T");
        testing.assertTrue($b.chapters[0].wellFormed);
        testing.assertEqual($b.chapters[0].title, "P\u00e4ge \U0001D11E");
        testing.assertEqual(text($b.chapters[0]), "Caf\u00e9");
    }
    def odd as bytes init binary.concat(utf16(PAGE, "le"), bytesOf("x"));
    def lone as bytes init encoding.fromText("hex", "fffe3c0000d83e00");
    for (def bad in [$odd, $lone]) {
        testing.assertEqual(
            readReason(handMade([
                File{
                    name: "META-INF/container.xml",
                    data: bytesOf(containerFor("OPS/package.opf"))
                },
                File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))},
                File{name: "OPS/ch.xhtml", data: $bad}
            ])),
            "content");
    }
}

# A file whose name starts with two dots is inside the book; only a `..`
# segment climbs out of it.
func testANameStartingWithTwoDotsIsInsideTheBook() {
    def opf as string init strings.replace(
        opfWith(META, ""),
        'href="ch.xhtml"',
        'href="..ch.xhtml"');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("package.opf"))},
        File{name: "package.opf", data: bytesOf($opf)},
        File{name: "..ch.xhtml", data: bytesOf(PAGE)}
    ]));
    testing.assertEqual($b.chapters[0].href, "..ch.xhtml");
    testing.assertTrue(climbsOut("../ch.xhtml"));
    testing.assertTrue(climbsOut(".."));
    testing.assertFalse(climbsOut("..ch.xhtml"));
}

# --- tolerances: read, and noted ------------------------------------------------

# The files of the minimal book, `mimetype` aside.
func minimalFiles() {
    return [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)}
    ];
}

# A `mimetype` that is right in content but not in form (deflated, not the
# first entry, followed by a newline) is read, with a note saying so. Before,
# each was refused with reason "container". A missing one, or other content,
# is still refused.
func testAnImperfectMimetypeIsReadWithANote() {
    def files as list of File init minimalFiles();
    def last as bytes init zipOf(
        lists.concat($files, [File{name: "mimetype", data: bytesOf(MIMETYPE)}]),
        false);
    def b as Book init read($last);
    testing.assertEqual($b.notes, ["the mimetype entry is not the first entry; read anyway"]);
    def nl as bytes init zipOf(
        lists.concat([File{name: "mimetype", data: bytesOf(MIMETYPE + "\n")}], $files),
        false);
    testing.assertEqual(
        read($nl).notes,
        ["the mimetype entry is followed by whitespace; read anyway"]);
    def all as list of archive.Entry;
    $all[] = archive.Entry{name: "mimetype", data: bytesOf(MIMETYPE), mode: 0, mtime: 0};
    for (def f in $files) {
        $all[] = archive.Entry{name: $f.name, data: $f.data, mode: 0, mtime: 0};
    }
    def packed as bytes init archive.pack("zip", $all);
    if ($packed[8] == 8) {
        testing.assertEqual(read($packed).notes, ["the mimetype entry is compressed; read anyway"]);
    }
    testing.assertEqual(readReason(zipOf($files, false)), "container");
    def wrong as bytes init zipOf(
        lists.concat([File{name: "mimetype", data: bytesOf("application/zip")}], $files),
        false);
    testing.assertEqual(readReason($wrong), "container");
    testing.assertEqual(read(minimalBook(PAGE, [])).notes, []);
}

# A manifest item whose file the archive lacks is left out, with a note;
# before, the whole book was refused. A spine item that names it still is.
func testAMissingManifestFileIsLeftOutWithANote() {
    def b as Book init read(withOpf(opfWith(
        META,
        '<item id="x" href="gone.png" media-type="image/png"/>')));
    testing.assertEqual(len($b.resources), 0);
    testing.assertEqual(len($b.notes), 1);
    testing.assertContains(
        $b.notes[0],
        'manifest item "x" names "OPS/gone.png", which is not in the archive; left out');
    def inSpine as string init strings.replace(
        opfWith(META, '<item id="x" href="gone.xhtml" media-type="application/xhtml+xml"/>'),
        '<itemref idref="c1"/>',
        '<itemref idref="c1"/><itemref idref="x"/>');
    testing.assertEqual(readReason(withOpf($inSpine)), "package");
    def ncxGone as string init strings.replace(
        opfWith(META, '<item id="n" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'),
        "<spine>",
        '<spine toc="n">');
    def c as Book init read(withOpf($ncxGone));
    testing.assertFalse($c.ncx);
    testing.assertEqual(len($c.notes), 1);
}

# A manifest href that matches an archive name only when case is ignored
# reads that file, with a note; before, the book was refused. When several
# names match, it still is.
func testAFileFoundIgnoringCaseIsReadWithANote() {
    def opf as string init strings.replace(opfWith(META, ""), 'href="ch.xhtml"', 'href="CH.xhtml"');
    def files as list of File init [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)}
    ];
    def b as Book init read(handMade($files));
    testing.assertEqual($b.chapters[0].href, "CH.xhtml");
    testing.assertEqual($b.chapters[0].title, "Page");
    testing.assertContains(
        $b.notes[0],
        '"OPS/CH.xhtml"; read "OPS/ch.xhtml", which differs only in case');
    $files[] = File{name: "OPS/Ch.xhtml", data: bytesOf(PAGE)};
    testing.assertEqual(readReason(handMade($files)), "package");
}

# The minimal book with these chapter bytes.
func withChapter(data as bytes) {
    return handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf(opfWith(META, ""))},
        File{name: "OPS/ch.xhtml", data: $data}
    ]);
}

# A chapter in a legacy charset it declares (XML declaration, `<meta
# charset>`, `http-equiv`) is decoded with it, with a note; before, it was
# refused. Undeclared, it still is. A package document or NCX may declare
# one in its XML declaration.
func testDeclaredLegacyCharsetsAreDecoded() {
    def latin as bytes init encoding.encode(
        "iso-8859-1",
        '<?xml version="1.0" encoding="ISO-8859-1"?><html xmlns="http://www.w3.org/1999/xhtml">' +
            "<head><title>Caf\u00e9</title></head><body><p>na\u00efve</p></body></html>");
    def b as Book init read(withChapter($latin));
    testing.assertEqual($b.chapters[0].title, "Caf\u00e9");
    testing.assertEqual(text($b.chapters[0]), "na\u00efve");
    testing.assertContains($b.notes[0], '"OPS/ch.xhtml" is not UTF-8; read as iso-8859-1');
    def meta as bytes init encoding.encode(
        "windows-1252",
        '<html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1252">' +
            "<title>\u201cQ\u201d</title></head><body><p>\u20ac</p></body></html>");
    def c as Book init read(withChapter($meta));
    testing.assertEqual(text($c.chapters[0]), "\u20ac");
    testing.assertFalse($c.chapters[0].wellFormed);
    def bare as bytes init encoding.encode("iso-8859-1", "<p>caf\u00e9</p>");
    testing.assertEqual(readReason(withChapter($bare)), "content");
    def opf as bytes init encoding.encode(
        "windows-1252",
        strings.replace(
            opfWith(
                '<dc:identifier id="uid">urn:x:1</dc:identifier>' +
                    "<dc:title>Caf\u00e9</dc:title>" +
                    "<dc:language>fr</dc:language>",
                ""),
            '<?xml version="1.0"?>',
            '<?xml version="1.0" encoding="windows-1252"?>'));
    def d as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: $opf},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)}
    ]));
    testing.assertEqual($d.title, "Caf\u00e9");
    testing.assertContains($d.notes[0], "read as windows-1252");
}

# An href starting with `/` is relative to the container root; before, it was
# joined to the package directory (`OPS/OPS/x.png`) and the book refused.
func testAnAbsoluteManifestHrefIsFromTheRoot() {
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{
            name: "OPS/package.opf",
            data: bytesOf(opfWith(
                META,
                '<item id="x" href="/OPS/img/x.png" media-type="image/png"/>' +
                    '<item id="y" href="/top.png" media-type="image/png"/>'))
        },
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/img/x.png", data: bytesOf("x")},
        File{name: "top.png", data: bytesOf("y")}
    ]));
    testing.assertEqual($b.notes, []);
    testing.assertEqual(resource($b, "img/x.png").data, bytesOf("x"));
    testing.assertEqual(resource($b, "../top.png").data, bytesOf("y"));
    testing.assertEqual(relativeTo("", "a/b.png"), "a/b.png");
    testing.assertEqual(relativeTo("OPS/text", "OPS/img/a.png"), "../../OPS/img/a.png");
}

# --- the table of contents -------------------------------------------------

func testTheNavigationDocumentIsReadAsHtml() {
    def nav as string init '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" ' +
        'xmlns:epub="http://www.idpf.org/2007/ops"><body>' +
        '<nav epub:type="landmarks"><ol><li><a href="../ch.xhtml">Skip me</a></li></ol></nav>' +
        '<nav epub:type="toc"><h1>Contents</h1><ol>' +
        '<li><a href="../ch.xhtml"><span>1.</span>&nbsp;The   start</a>' +
        '<ol><li><a href="../ch.xhtml#a">Sub&mdash;part</a></li></ol></li>' +
        '<li><span>Group</span><ol><li><a href="../ch.xhtml#b">B</a></li></ol></li>' +
        '</ol></nav></body></html>';
    def b as Book init read(minimalBook(
        PAGE,
        [File{name: "OPS/nav/nav.xhtml", data: bytesOf($nav)}]));
    testing.assertEqual(len($b.toc), 0);
    def opf as string init opfWith(
        META,
        '<item id="n" href="nav/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>');
    $b = read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/nav/nav.xhtml", data: bytesOf($nav)}
    ]));
    testing.assertEqual(
        $b.toc,
        [
            TocEntry{title: "1. \u00A0The start", href: "ch.xhtml", level: 0},
            TocEntry{title: "Sub\u2014part", href: "ch.xhtml#a", level: 1},
            TocEntry{title: "Group", href: "", level: 0},
            TocEntry{title: "B", href: "ch.xhtml#b", level: 1}
        ]);
    testing.assertEqual($b.chapters[0].title, "1. \u00A0The start");
    # The navigation document is the table of contents, not a resource.
    testing.assertEqual(len($b.resources), 0);
    testing.assertFalse($b.ncx);
}

func testAnNcxIsReadStrictly() {
    def ncx as string init '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">' +
        '<head/><docTitle><text>T</text></docTitle><navMap>' +
        '<navPoint id="a" playOrder="1"><navLabel><text>One</text></navLabel><content src="ch.xhtml"/>' +
        '<navPoint id="b" playOrder="2"><navLabel><text> Inner </text></navLabel><content src="ch.xhtml#i"/></navPoint>' +
        '</navPoint></navMap></ncx>';
    def opf as string init strings.replace(
        opfWith(META, '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'),
        "<spine>",
        '<spine toc="toc">');
    def files as list of File init [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)}
    ];
    def good as list of File init $files;
    $good[] = File{name: "OPS/toc.ncx", data: bytesOf($ncx)};
    def b as Book init read(handMade($good));
    testing.assertTrue($b.ncx);
    testing.assertEqual(
        $b.toc,
        [
            TocEntry{title: "One", href: "ch.xhtml", level: 0},
            TocEntry{title: "Inner", href: "ch.xhtml#i", level: 1}
        ]);
    def bad as list of File init $files;
    $bad[] = File{name: "OPS/toc.ncx", data: bytesOf("<ncx><navMap>&nbsp;</navMap></ncx>")};
    testing.assertEqual(readReason(handMade($bad)), "toc");
    def empty as list of File init $files;
    $empty[] = File{name: "OPS/toc.ncx", data: bytesOf("<ncx/>")};
    testing.assertEqual(readReason(handMade($empty)), "toc");
}

# --- DRM and obfuscation ---------------------------------------------------

def const ADEPT_ENCRYPTION as string init '<?xml version="1.0"?>' +
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
    '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">' +
    '<EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>' +
    '<KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#"><resource xmlns="http://ns.adobe.com/adept">urn:uuid:1</resource></KeyInfo>' +
    '<CipherData><CipherReference URI="OPS/ch.xhtml"/></CipherData></EncryptedData></encryption>';

func encryptionFor(algorithm as string, uri as string) {
    return '<?xml version="1.0"?><encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
        '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">' +
        '<EncryptionMethod Algorithm="' + $algorithm + '"/>' +
        '<CipherData><CipherReference URI="' + $uri +
        '"/></CipherData></EncryptedData></encryption>';
}

func testADrmProtectedBookIsRefused() {
    def enc as File init File{name: "META-INF/encryption.xml", data: bytesOf(ADEPT_ENCRYPTION)};
    testing.assertEqual(readReason(minimalBook(PAGE, [$enc])), "drm");
    def rights as File init File{name: "META-INF/rights.xml", data: bytesOf("<rights/>")};
    testing.assertEqual(readReason(minimalBook(PAGE, [$rights])), "drm");
    def lcp as File init File{name: "META-INF/license.lcpl", data: bytesOf('{}')};
    testing.assertEqual(readReason(minimalBook(PAGE, [$lcp])), "drm");
    def broken as File init File{name: "META-INF/encryption.xml", data: bytesOf("<encryption>")};
    testing.assertEqual(readReason(minimalBook(PAGE, [$broken])), "container");
    try {
        read(minimalBook(PAGE, [$enc]));
    } catch (e) {
        testing.assertContains($e.message, "aes128-cbc");
    }
}

# A font obfuscated as the specification says, computed here byte by byte
# rather than with the code under test.
func obfuscated(font as bytes, key as bytes, n as int) {
    def out as bytes;
    for (def i in 0..len($font)) {
        if ($i < $n) {
            $out[] = $font[$i] ^ $key[$i % len($key)];
        } else {
            $out[] = $font[$i];
        }
    }
    return $out;
}

func bookWithFont(uid as string, algorithm as string, font as bytes) {
    def meta as string init '<dc:identifier id="uid">' + $uid + '</dc:identifier>' +
        '<dc:title>T</dc:title><dc:language>en</dc:language>';
    return handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{
            name: "META-INF/encryption.xml",
            data: bytesOf(encryptionFor($algorithm, "OPS/f.otf"))
        },
        File{
            name: "OPS/package.opf",
            data: bytesOf(opfWith($meta, '<item id="f" href="f.otf" media-type="font/otf"/>'))
        },
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/f.otf", data: $font}
    ]);
}

func testIdpfFontObfuscationIsUndone() {
    def font as bytes init bytesOf("OTTO" + strings.replicate("glyph data ", 120));
    def uid as string init "urn:uuid:00000000-1111-2222-3333-444444444444";
    # The key is the SHA-1 of the identifier with its whitespace removed.
    def key as bytes init hash.compute("sha1", bytesOf($uid));
    def data as bytes init bookWithFont(
        " " + $uid + "\n",
        IDPF_OBFUSCATION,
        obfuscated($font, $key, 1040));
    testing.assertEqual(resource(read($data), "f.otf").data, $font);
}

func testAdobeFontObfuscationIsUndone() {
    def font as bytes init bytesOf("wOFF" + strings.replicate("x", 2000));
    def uid as string init "urn:uuid:0123abcd-4567-89ef-0123-456789abcdef";
    def key as bytes init encoding.fromText("hex", "0123abcd456789ef0123456789abcdef");
    def data as bytes init bookWithFont($uid, ADOBE_OBFUSCATION, obfuscated($font, $key, 1024));
    testing.assertEqual(resource(read($data), "f.otf").data, $font);
    testing.assertEqual(readReason(bookWithFont("isbn:1", ADOBE_OBFUSCATION, $font)), "package");
}

# A font shorter than the obfuscated span is XORed as far as it goes.
func testAShortObfuscatedFontIsRestored() {
    def font as bytes init bytesOf("tiny");
    def key as bytes init hash.compute("sha1", bytesOf("urn:x:1"));
    testing.assertEqual(
        deobfuscate(obfuscated($font, $key, 1040), IDPF_OBFUSCATION, "urn:x:1", []),
        $font);
}

# --- archive safety and caps -----------------------------------------------

func testAZipSlipNameIsRefused() {
    def evil as File init File{name: "../evil.txt", data: bytesOf("x")};
    testing.assertEqual(readReason(minimalBook(PAGE, [$evil])), "archive");
    def twice as File init File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)};
    testing.assertEqual(readReason(minimalBook(PAGE, [$twice])), "archive");
}

func testCapsAreLimitErrors() {
    def data as bytes init build(sampleBook());
    def o as ReadOptions init readOptions();
    testing.assertEqual($o.maxBytes, DEFAULT_MAX_BYTES);
    testing.assertEqual($o.maxEntries, DEFAULT_MAX_ENTRIES);
    testing.assertEqual($o.maxEntryBytes, DEFAULT_MAX_ENTRY_BYTES);
    testing.assertEqual($o.maxTotalBytes, DEFAULT_MAX_TOTAL_BYTES);
    $o.maxBytes = 100;
    testing.assertThrowsArgs("readWith", [$data, $o], "limit");
    $o = readOptions();
    $o.maxEntries = 3;
    testing.assertThrowsArgs("readWith", [$data, $o], "limit");
    $o = readOptions();
    $o.maxEntryBytes = 100;
    testing.assertThrowsArgs("readWith", [$data, $o], "limit");
    $o = readOptions();
    $o.maxTotalBytes = 1000;
    testing.assertThrowsArgs("readWith", [$data, $o], "limit");
    # Zero takes the default, a negative value lifts the cap.
    $o = ReadOptions{maxBytes: 0, maxEntries: 0, maxEntryBytes: 0, maxTotalBytes: 0};
    testing.assertEqual(readWith($data, $o).title, "A Book");
    $o = ReadOptions{maxBytes: -1, maxEntries: -1, maxEntryBytes: -1, maxTotalBytes: -1};
    testing.assertEqual(readWith($data, $o).title, "A Book");
}

# --- lookups ---------------------------------------------------------------

func testResourcesAreFoundByHref() {
    def b as Book init read(build(richBook()));
    testing.assertEqual(textOf(resource($b, "img/cover.png").data), "PNGDATA");
    testing.assertEqual(textOf(resource($b, "img/./dot.png#x").data), "PNG");
    testing.assertThrowsArgs("resource", [$b, "nope.png"], "epub");
    try {
        resource($b, "nope.png");
    } catch (e) {
        testing.assertEqual($e.reason, "missing");
    }
}

func testLinksResolveAgainstTheirFile() {
    testing.assertEqual(resolve("text/ch1.xhtml", "../img/a.png"), "img/a.png");
    testing.assertEqual(resolve("text/ch1.xhtml", "ch2.xhtml#s"), "text/ch2.xhtml#s");
    testing.assertEqual(resolve("text/ch1.xhtml", "#top"), "text/ch1.xhtml#top");
    testing.assertEqual(resolve("ch1.xhtml", "a%20b.png"), "a b.png");
    testing.assertEqual(resolve("ch1.xhtml", "https://example.org/x"), "https://example.org/x");
    testing.assertEqual(resolve("ch1.xhtml", "mailto:a@b.c"), "mailto:a@b.c");
}

# --- round 5: mislabels, landmarks, page lists, fallbacks, renditions --------

# Valid UTF-8 that declares Latin-1 is read as UTF-8, and the mismatch is a
# note; before, it was read silently. Pure ASCII, the same in both, is not
# noted.
func testAUtf8DocumentLabelledLatin1IsNoted() {
    def page as string init '<?xml version="1.0" encoding="iso-8859-1"?>' +
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title></head>' +
        "<body><p>Café</p></body></html>";
    def b as Book init read(withChapter(bytesOf($page)));
    testing.assertEqual(text($b.chapters[0]), "Café");
    testing.assertEqual(
        $b.notes,
        ['"OPS/ch.xhtml" declares iso-8859-1 but is valid UTF-8; read as UTF-8']);
    def ascii as string init strings.replace($page, "Café", "Cafe");
    testing.assertEqual(read(withChapter(bytesOf($ascii))).notes, []);
}

# The nav's landmarks and page list are read, hrefs resolved against it.
func testLandmarksAndPagesAreReadFromTheNav() {
    def nav as string init '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" ' +
        'xmlns:epub="http://www.idpf.org/2007/ops"><body>' +
        '<nav epub:type="toc"><ol><li><a href="../ch.xhtml">One</a></li></ol></nav>' +
        '<nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="../ch.xhtml">Begin</a></li>' +
        '<li><a epub:type="toc" href="nav.xhtml#toc">Contents</a></li></ol></nav>' +
        '<nav epub:type="page-list"><ol><li><a href="../ch.xhtml#p1">1</a></li>' +
        '<li><a href="../ch.xhtml#p2">ii</a></li></ol></nav></body></html>';
    def b as Book init read(minimalBook(
        PAGE,
        [File{name: "OPS/toc/nav.xhtml", data: bytesOf($nav)}]));
    testing.assertEqual(len($b.toc), 0);
    def opf as string init opfWith(
        META,
        '<item id="nav" href="toc/nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>');
    def c as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/toc/nav.xhtml", data: bytesOf($nav)}
    ]));
    testing.assertEqual(
        $c.landmarks,
        [
            Landmark{type: "bodymatter", title: "Begin", href: "ch.xhtml"},
            Landmark{type: "toc", title: "Contents", href: "toc/nav.xhtml#toc"}
        ]);
    testing.assertEqual(
        $c.pages,
        [PageTarget{label: "1", href: "ch.xhtml#p1"}, PageTarget{label: "ii", href: "ch.xhtml#p2"}]);
}

# An EPUB 2 book's `<guide>` gives its landmarks, types mapped to EPUB 3
# names, and its NCX `<pageList>` its pages.
func testTheGuideAndTheNcxPageListAreRead() {
    def ncx as string init '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">' +
        '<head/><docTitle><text>T</text></docTitle><navMap><navPoint id="a" playOrder="1">' +
        '<navLabel><text>One</text></navLabel><content src="ch.xhtml"/></navPoint></navMap>' +
        '<pageList><pageTarget id="p1" type="normal" value="1" playOrder="2"><navLabel><text>1</text>' +
        '</navLabel><content src="ch.xhtml#p1"/></pageTarget></pageList></ncx>';
    def opf as string init strings.replace(
        strings.replace(
            opfWith(META, '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'),
            "<spine>",
            '<spine toc="ncx">'),
        "</spine>",
        '</spine><guide><reference type="text" title="Start" href="ch.xhtml"/>' +
            '<reference type="other.x" title="X" href="ch.xhtml#x"/></guide>');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/toc.ncx", data: bytesOf($ncx)}
    ]));
    testing.assertEqual(
        $b.landmarks,
        [
            Landmark{type: "bodymatter", title: "Start", href: "ch.xhtml"},
            Landmark{type: "other.x", title: "X", href: "ch.xhtml#x"}
        ]);
    testing.assertEqual($b.pages, [PageTarget{label: "1", href: "ch.xhtml#p1"}]);
}

# A spine item of a non-core type follows its `fallback` chain to an XHTML
# or SVG document, with a note; a loop or a chain without one is refused. A
# picture keeps its place (the samples' comics all fall back to one generic
# page), and so does an item whose fallback is in the spine already.
func testASpineFallbackChainIsFollowed() {
    def items as string init '<item id="p" href="p.dtb" media-type="application/x-custom" fallback="q"/>' +
        '<item id="q" href="q.gif" media-type="image/gif" fallback="c2"/>' +
        '<item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>';
    def opf as string init strings.replace(
        opfWith(META, $items),
        '<itemref idref="c1"/>',
        '<itemref idref="c1"/><itemref idref="p"/>');
    def files as list of File init [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/ch2.xhtml", data: bytesOf(strings.replace(PAGE, "Page", "Two"))},
        File{name: "OPS/p.dtb", data: bytesOf("dtb")},
        File{name: "OPS/q.gif", data: bytesOf("gif")}
    ];
    def b as Book init read(handMade($files));
    testing.assertEqual($b.chapters[1].href, "ch2.xhtml");
    testing.assertEqual($b.chapters[1].title, "Two");
    testing.assertContains(
        $b.notes[0],
        'spine item "p" is application/x-custom; read its fallback "c2"');
    testing.assertEqual(len($b.resources), 2);
    def picture as string init strings.replace(
        $opf,
        '<itemref idref="p"/>',
        '<itemref idref="q"/>');
    $files[1] = File{name: "OPS/package.opf", data: bytesOf($picture)};
    def c as Book init read(handMade($files));
    testing.assertEqual($c.chapters[1].href, "q.gif");
    testing.assertEqual($c.notes, []);
    def twice as string init strings.replace(
        $opf,
        '<itemref idref="p"/>',
        '<itemref idref="c2"/><itemref idref="p"/>');
    $files[1] = File{name: "OPS/package.opf", data: bytesOf($twice)};
    def d as Book init read(handMade($files));
    testing.assertEqual($d.chapters[2].href, "p.dtb");
    testing.assertContains($d.notes[0], "is in the spine already");
    $files[1] = File{
        name: "OPS/package.opf",
        data: bytesOf(strings.replace($opf, 'fallback="c2"', 'fallback="p"'))
    };
    testing.assertEqual(readReason(handMade($files)), "package");
    $files[1] = File{
        name: "OPS/package.opf",
        data: bytesOf(strings.replace($opf, ' fallback="c2"', ""))
    };
    testing.assertEqual(readReason(handMade($files)), "package");
}

# The package's rendition metadata and the itemrefs' properties are read.
func testRenditionPropertiesAreRead() {
    def opf as string init strings.replace(
        strings.replace(
            opfWith(
                META + '<meta property="rendition:layout">pre-paginated</meta>' +
                    '<meta property="rendition:spread">landscape</meta>' +
                    '<meta refines="#x" property="rendition:layout">reflowable</meta>',
                ""),
            '<itemref idref="c1"/>',
            '<itemref idref="c1" properties="page-spread-left"/>'),
        "<spine>",
        '<spine page-progression-direction="rtl">');
    def page as string init strings.replace(
        PAGE,
        "<title>",
        '<meta name="viewport" content="width=600, height=800"/><title>');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf($page)}
    ]));
    testing.assertEqual($b.layout, "pre-paginated");
    testing.assertEqual($b.spread, "landscape");
    testing.assertEqual($b.orientation, "");
    testing.assertEqual($b.chapters[0].spineProperties, "page-spread-left");
    testing.assertEqual($b.viewport, "width=600, height=800");
    testing.assertEqual($b.direction, "rtl");
}

# The book's own navigation document is kept as a file when a chapter links
# into it (an index pointing at its entries), and `writable` makes it a
# chapter out of the reading order, renamed from nav.xhtml and the links to
# it following. Before, `read` dropped it and the links led nowhere.
func testALinkedNavigationDocumentIsKept() {
    def nav as string init '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" ' +
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title></head><body>' +
        '<nav epub:type="toc"><ol><li><a href="ch.xhtml">One</a></li></ol></nav>' +
        '<p id="books">Books</p></body></html>';
    def page as string init strings.replace(
        PAGE,
        "<p>Hello.</p>",
        '<p><a href="nav.xhtml#books">see</a></p>');
    def opf as string init opfWith(
        META,
        '<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>');
    def files as list of File init [
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf($page)},
        File{name: "OPS/nav.xhtml", data: bytesOf($nav)}
    ];
    def b as Book init read(handMade($files));
    testing.assertEqual(len($b.resources), 1);
    testing.assertEqual($b.resources[0].href, "nav.xhtml");
    def w as Book init writable($b);
    testing.assertEqual($w.chapters[1].href, "nav-old.xhtml");
    testing.assertFalse($w.chapters[1].linear);
    testing.assertContains($w.chapters[0].content, '<a href="nav-old.xhtml#books">see</a>');
    testing.assertEqual(len($w.notes), 2);
    def back as Book init read(build($w));
    testing.assertEqual(len($back.chapters), 2);
    testing.assertEqual(check($back), []);
    # Not linked, it is left out as before.
    $files[2] = File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)};
    testing.assertEqual(len(read(handMade($files)).resources), 0);
}

# A media overlay is read: the chapter's `media-overlay`, the SMIL file among
# the resources, and the `media:` metadata with what they refine.
func testMediaOverlaysAreRead() {
    def opf as string init strings.replace(
        opfWith(
            META + '<meta property="media:duration" refines="#mo">0:00:05</meta>' +
                '<meta property="media:narrator">Ann</meta>',
            '<item id="mo" href="ch.smil" media-type="application/smil+xml"/>'),
        '<item id="c1" href="ch.xhtml" media-type="application/xhtml+xml"/>',
        '<item id="c1" href="ch.xhtml" media-type="application/xhtml+xml" media-overlay="mo"/>');
    def b as Book init read(handMade([
        File{name: "META-INF/container.xml", data: bytesOf(containerFor("OPS/package.opf"))},
        File{name: "OPS/package.opf", data: bytesOf($opf)},
        File{name: "OPS/ch.xhtml", data: bytesOf(PAGE)},
        File{name: "OPS/ch.smil", data: bytesOf("<smil/>")}
    ]));
    testing.assertEqual($b.chapters[0].mediaOverlay, "mo");
    testing.assertEqual($b.resources[0].mediaType, "application/smil+xml");
    testing.assertEqual(
        $b.mediaMeta,
        [
            Meta{property: "media:duration", refines: "#mo", value: "0:00:05"},
            Meta{property: "media:narrator", refines: "", value: "Ann"}
        ]);
}

# A navigation document nesting 121 levels is read with an explicit stack;
# before, `navItems` recursed once per level, past the tiny build's 120
# nested calls. At two elements a level, plus `html`, `body`, `nav`, `ol`
# and the last `li` and `a`, it is 248 elements deep, under the `html`
# parser's nesting cap (256 from Jennifer 0.28.0 on, 512 before); 300
# levels are past both, kind "limit". On the tiny build the 121-level parse
# stops first, at the value nesting cap, as kind "limit" too. An NCX
# nesting 50 (under the tiny build's `xml` cap of 64) is read on both.
func testDeepTablesOfContentsAreReadWithoutRecursion() {
    testing.assertEqual(navKind(navNested(300)), "limit");
    def nav as string init navNested(121);
    if (meta.BUILD == "tinygo") {
        testing.assertEqual(navKind($nav), "limit");
    } else {
        def got as list of TocEntry init navRead($nav, "toc/nav.xhtml").toc;
        testing.assertEqual(len($got), 122);
        testing.assertEqual($got[121].level, 121);
        testing.assertEqual($got[121].title, "Last");
    }
    def points as string init "";
    for (def i in 0..50) {
        $points = $points + '<navPoint><navLabel><text>P</text></navLabel><content src="ch.xhtml"/>';
    }
    def ncx as xml.Value init xml.decode('<ncx><navMap>' + $points +
        strings.replicate("</navPoint>", 50) + "</navMap></ncx>");
    def entries as list of TocEntry init ncxToc($ncx, "toc.ncx", "toc.ncx");
    testing.assertEqual(len($entries), 50);
    testing.assertEqual($entries[49].level, 49);
}

# A navigation document whose table of contents nests `levels` deep.
func navNested(levels as int) {
    def items as string init "";
    for (def i in 0..$levels) {
        $items = $items + '<li><a href="../ch.xhtml">L</a><ol>';
    }
    $items = $items + '<li><a href="../ch.xhtml">Last</a></li>' +
        strings.replicate("</ol></li>", $levels);
    return '<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>' +
        $items + "</ol></nav></body></html>";
}

# The kind `navRead` throws for a navigation document, "" when it reads.
func navKind(nav as string) {
    try {
        navRead($nav, "toc/nav.xhtml");
    } catch (e) {
        return $e.kind;
    }
    return "";
}

# A chapter nested past the `xml` parser's cap is read as HTML rather than
# refusing the book, as long as the `html` parser (256 levels from Jennifer
# 0.28.0 on, 512 before) takes it. On
# the default build the `xml` cap (1000) is above the `html` one, so a
# chapter past it is still "limit". On the tiny build the `xml` cap is 64,
# but the interpreter's value nesting cap stops the `html` parse at about 31
# elements, so a chapter past 64 levels is "limit" there too.
func deepPage(depth as int) {
    return '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Deep</title></head><body>' +
        strings.replicate("<div>", $depth) + "<p>x</p>" + strings.replicate("</div>", $depth) +
        "</body></html>";
}

func testAChapterTooDeepForXmlIsReadAsHtml() {
    if (meta.BUILD == "tinygo") {
        testing.assertEqual(readReason(withChapter(bytesOf(deepPage(65)))), "kind:limit");
        return;
    }
    def b as Book init read(withChapter(bytesOf(deepPage(65))));
    testing.assertTrue($b.chapters[0].wellFormed);
    testing.assertEqual($b.chapters[0].title, "Deep");
    testing.assertEqual(text($b.chapters[0]), "x");
    testing.assertEqual(readReason(withChapter(bytesOf(deepPage(1001)))), "kind:limit");
}
