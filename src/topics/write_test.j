# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# epub - white-box tests for writing: the builders, the documents and
# `build`. The first tests are ported from Grimoire's EPUB renderer. Spliced
# into epub_test.j via include.

func digestOf(data as bytes) {
    return encoding.toText("hex", hash.compute("sha256", $data));
}

# A small book with two chapters, one in a subdirectory, and a picture.
func sampleBook() {
    def b as Book init book("A Book", "en");
    $b = author($b, "Ada");
    $b = markdownChapter($b, "intro.xhtml", "Intro", "# Intro\n\nSee *this*.\n");
    $b = chapter($b, "text/two.xhtml", "Two", '<h1 id="t">Two</h1><p>x<br/>y</p>');
    $b = image($b, "img/dot.png", bytesOf("PNG"));
    return $b;
}

func entryOf(data as bytes, name as string) {
    for (def e in archive.unpack("zip", $data)) {
        if ($e.name == $name) {
            return textOf($e.data);
        }
    }
    return "";
}

# The whole point of a content document: it has to be XML, not HTML5. The
# renderer writes it that way and this parses the result back rather than
# grepping for a closing slash, because "well formed" is a parser's judgement.
func testAChapterIsAWellFormedXmlDocument() {
    def b as Book init markdownChapter(
        book("B", "en"),
        "c.xhtml",
        "Intro",
        "# T\n\nA line,\n\n---\n\n![p](x.png) and `code`.\n");
    def out as string init $b.chapters[0].content;
    testing.assertContains($out, '<?xml version="1.0" encoding="utf-8"?>');
    testing.assertContains($out, "<!DOCTYPE html>");
    testing.assertContains($out, '<img src="x.png" alt="p"/>');
    testing.assertContains($out, "<hr/>");
    def doc as xml.Value init xml.decode($out);
    testing.assertEqual(xml.tag($doc), "html");
    testing.assertEqual(xml.namespace($doc), XHTML_NS);
}

# The body is decoded with the XHTML namespace as its default, so it stays in
# that namespace inside the page; decoded without it, it was written out as
# `<body xmlns="">`, an element no reader knows.
func testTheBodyStaysInTheXhtmlNamespace() {
    def b as Book init chapter(book("B", "en"), "c.xhtml", "C", '<p epub:type="note">n</p>');
    def out as string init $b.chapters[0].content;
    testing.assertFalse(strings.contains($out, 'xmlns=""'));
    testing.assertContains($out, '<p epub:type="note">n</p>');
    def doc as xml.Value init xml.decode($out);
    def x as map of string to string init {"x": XHTML_NS};
    testing.assertEqual(xml.namespace(xml.get($doc, "x:body/x:p", $x)), XHTML_NS);
}

# The navigation document is the one place `epub:type` is always written, and
# its prefix is declared on the `<html>` element.
func testTheNavigationDocumentIsWellFormedWithItsPrefixDeclared() {
    def b as Book init sampleBook();
    def out as string init navXhtml($b, tocOf($b));
    testing.assertContains($out, 'xmlns:epub="http://www.idpf.org/2007/ops"');
    testing.assertContains($out, '<nav epub:type="toc" id="toc">');
    testing.assertContains($out, '<a href="intro.xhtml">Intro</a>');
    testing.assertContains($out, '<a href="text/two.xhtml">Two</a>');
    testing.assertEqual(xml.tag(xml.decode($out)), "html");
}

# Whitespace inside a `<pre>` is content, so the document is not
# pretty-printed, and the code block's language reaches it as a class.
func testCodeBlocksKeepTheirWhitespaceAndTheirLanguage() {
    def b as Book init markdownChapter(
        book("B", "en"),
        "c.xhtml",
        "C",
        "```sh\nls -l\n\n    indented\n```\n");
    testing.assertContains(
        $b.chapters[0].content,
        '<pre><code class="language-sh">' + "ls -l\n\n    indented" + "</code></pre>");
}

func chapterThatIsNotXml() {
    chapter(book("B", "en"), "c.xhtml", "C", "<p>unclosed");
}

func chapterWithAnHtmlEntity() {
    chapter(book("B", "en"), "c.xhtml", "C", "<p>a&nbsp;b</p>");
}

func testAChapterThatIsNotXmlIsRefused() {
    testing.assertThrows("chapterThatIsNotXml", "epub");
    testing.assertThrows("chapterWithAnHtmlEntity", "epub");
    try {
        chapterThatIsNotXml();
    } catch (e) {
        testing.assertEqual($e.reason, "content");
        testing.assertContains($e.message, '"c.xhtml"');
    }
}

# Escaping is the `xml` library's. What is tested is that the text reaching
# markup goes through it.
func testTextThatLooksLikeMarkupIsEscaped() {
    def b as Book init book('Tom & Jerry <"quoted">', "en");
    $b = author($b, "Ada & Grace");
    $b.description = "A <description>";
    $b = chapter($b, "c.xhtml", "Tom & Jerry", "<p>body</p>");
    testing.assertFalse(strings.contains($b.chapters[0].content, "<title>Tom & Jerry"));
    testing.assertContains($b.chapters[0].content, "<title>Tom &amp; Jerry</title>");
    def opf as string init contentOpf($b);
    testing.assertContains($opf, "<dc:title>Tom &amp; Jerry &lt;\"quoted\"&gt;</dc:title>");
    testing.assertContains($opf, "<dc:creator>Ada &amp; Grace</dc:creator>");
    testing.assertContains($opf, "<dc:description>A &lt;description&gt;</dc:description>");
    testing.assertEqual(xml.tag(xml.decode($opf)), "package");
}

# No clock and no random source: the identifier is the book's own title and
# language, which is what makes a rebuild produce the same file.
func testTheIdentifierIsStableAndShaped() {
    def id as string init identifierFor("A Book", "en");
    testing.assertEqual($id, identifierFor("A Book", "en"));
    testing.assertNotEqual($id, identifierFor("A Book", "de"));
    testing.assertTrue(strings.startsWith($id, "urn:uuid:"));
    testing.assertEqual(len($id), 45);
    testing.assertEqual(book("A Book", "en").identifier, $id);
}

func testTheSameBookGivesTheSameBytes() {
    def b as Book init sampleBook();
    testing.assertEqual(digestOf(build($b)), digestOf(build($b)));
    testing.assertEqual(digestOf(build(sampleBook())), digestOf(build($b)));
}

func testTheBookIsLaidOutUnderOebps() {
    def data as bytes init build(sampleBook());
    def names as list of string;
    for (def e in archive.unpack("zip", $data)) {
        $names[] = $e.name;
    }
    testing.assertEqual(
        $names,
        [
            "mimetype",
            "META-INF/container.xml",
            "OEBPS/content.opf",
            "OEBPS/nav.xhtml",
            "OEBPS/intro.xhtml",
            "OEBPS/text/two.xhtml",
            "OEBPS/style.css",
            "OEBPS/img/dot.png"
        ]);
    testing.assertContains(
        entryOf($data, "META-INF/container.xml"),
        'full-path="OEBPS/content.opf"');
}

func testThePackageListsEverything() {
    def b as Book init cover(sampleBook(), "cover.jpg", bytesOf("JPG"));
    $b.publisher = "P";
    $b.date = "2026-11-14";
    def opf as string init contentOpf($b);
    testing.assertContains($opf, 'version="3.0"');
    testing.assertContains(
        $opf,
        '<dc:identifier id="pub-id">' + $b.identifier + "</dc:identifier>");
    testing.assertContains($opf, "<dc:language>en</dc:language>");
    testing.assertContains($opf, "<dc:publisher>P</dc:publisher>");
    testing.assertContains($opf, "<dc:date>2026-11-14</dc:date>");
    testing.assertContains($opf, '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>');
    testing.assertContains($opf, '<meta name="cover" content="cover-image"/>');
    testing.assertContains(
        $opf,
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>');
    testing.assertContains(
        $opf,
        '<item id="ch1" href="intro.xhtml" media-type="application/xhtml+xml"/>');
    testing.assertContains(
        $opf,
        '<item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>');
    testing.assertContains($opf, '<itemref idref="ch1"/>');
    testing.assertContains($opf, '<itemref idref="ch2"/>');
    testing.assertFalse(strings.contains($opf, "toc.ncx"));
}

func testAChapterInADirectoryLinksTheStylesheetUpwards() {
    def b as Book init sampleBook();
    testing.assertContains($b.chapters[0].content, 'href="style.css"');
    testing.assertContains($b.chapters[1].content, 'href="../style.css"');
    testing.assertEqual(upTo("a/b/c.xhtml"), "../../");
}

func testContentPropertiesFollowWhatAChapterHolds() {
    testing.assertEqual(contentProperties("<p>x</p>"), "");
    testing.assertEqual(contentProperties('<svg xmlns="http://www.w3.org/2000/svg"/>'), "svg");
    testing.assertEqual(
        contentProperties("<m:math>x</m:math><script>1</script>"),
        "mathml scripted");
    def b as Book init chapter(
        book("B", "en"),
        "c.xhtml",
        "C",
        '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
    testing.assertEqual($b.chapters[0].properties, "svg");
}

func testBuildersRefuseBadInput() {
    def b as Book init sampleBook();
    for (def bad in [
        "intro.xhtml",
        "img/dot.png",
        "nav.xhtml",
        "content.opf",
        "toc.ncx",
        "../x.xhtml"
    ]) {
        def got as string init "";
        try {
            chapter($b, $bad, "X", "<p/>");
        } catch (e) {
            $got = $e.reason;
        }
        testing.assertEqual($got, "input");
    }
    def got as list of string;
    try {
        book(" ", "en");
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        book("T", "not a tag");
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        author($b, "");
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        image($b, "notes.txt", bytesOf("x"));
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        file($b, "a.bin", "binary", bytesOf("x"));
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        cover(cover($b, "c1.png", bytesOf("x")), "c2.png", bytesOf("x"));
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        tocEntry($b, "", "intro.xhtml", 0);
    } catch (e) {
        $got[] = $e.reason;
    }
    try {
        tocEntry($b, "X", "intro.xhtml", -1);
    } catch (e) {
        $got[] = $e.reason;
    }
    testing.assertEqual(
        $got,
        ["input", "input", "input", "input", "input", "input", "input", "input"]);
}

func testFilesAndStylesheets() {
    def b as Book init file(book("B", "en"), "fonts/a.woff2", "font/woff2", bytesOf("F"));
    testing.assertEqual($b.resources[1].mediaType, "font/woff2");
    testing.assertEqual($b.resources[1].id, "res2");
    $b = stylesheet($b, 'p { margin: 0; }');
    testing.assertEqual(len($b.resources), 2);
    testing.assertEqual(textOf($b.resources[0].data), 'p { margin: 0; }');
    # A book whose stylesheet was taken out gets a new one.
    $b.resources = [$b.resources[1]];
    $b = stylesheet($b, 'p { }');
    testing.assertEqual($b.resources[1].href, CSS_HREF);
    testing.assertEqual($b.resources[1].id, "style1");
}

func testBuildRefusesABookItCannotWrite() {
    testing.assertEqual(buildReason(book("Empty", "en")), "input");
    def b as Book init sampleBook();
    $b.modified = "yesterday";
    testing.assertEqual(buildReason($b), "input");
    $b = sampleBook();
    $b.cover = "img/none.png";
    testing.assertEqual(buildReason($b), "input");
    $b = sampleBook();
    $b.chapters[1].id = "ch1";
    testing.assertEqual(buildReason($b), "input");
    $b = sampleBook();
    $b.resources[0].id = "nav";
    testing.assertEqual(buildReason($b), "input");
    $b = sampleBook();
    $b.resources[0].href = "intro.xhtml";
    testing.assertEqual(buildReason($b), "input");
    $b = sampleBook();
    $b.title = "";
    testing.assertEqual(buildReason($b), "input");
}

func testTheTableOfContentsListsTheChaptersByDefault() {
    def b as Book init sampleBook();
    $b = chapter($b, "untitled.xhtml", "", "<p>u</p>");
    def toc as list of TocEntry init tocOf($b);
    testing.assertEqual(len($toc), 3);
    testing.assertEqual($toc[0], TocEntry{title: "Intro", href: "intro.xhtml", level: 0});
    testing.assertEqual($toc[2].title, "untitled.xhtml");
    # The page title falls back to the book's.
    testing.assertContains($b.chapters[2].content, "<title>A Book</title>");
}

func testATableOfContentsNests() {
    def b as Book init sampleBook();
    $b = tocEntry($b, "Intro", "intro.xhtml", 0);
    $b = tocEntry($b, "Part", "", 0);
    $b = tocEntry($b, "Two", "text/two.xhtml", 1);
    $b = tocEntry($b, "Deep", "text/two.xhtml#t", 2);
    $b = tocEntry($b, "Back", "intro.xhtml#x", 1);
    def nav as string init navXhtml($b, tocOf($b));
    testing.assertContains(
        $nav,
        '<ol><li><a href="intro.xhtml">Intro</a></li><li><span>Part</span><ol>' +
            '<li><a href="text/two.xhtml">Two</a><ol><li><a href="text/two.xhtml#t">Deep</a></li></ol></li>' +
            '<li><a href="intro.xhtml#x">Back</a></li></ol></li></ol>');
    testing.assertEqual(buildReason($b), "");
}

func testABrokenTableOfContentsIsRefused() {
    def jump as Book init tocEntry(
        tocEntry(sampleBook(), "A", "intro.xhtml", 0),
        "B",
        "intro.xhtml",
        2);
    testing.assertEqual(buildReason($jump), "toc");
    def deepFirst as Book init tocEntry(sampleBook(), "A", "intro.xhtml", 1);
    testing.assertEqual(buildReason($deepFirst), "toc");
    def bare as Book init tocEntry(tocEntry(sampleBook(), "A", "", 0), "B", "intro.xhtml", 0);
    testing.assertEqual(buildReason($bare), "toc");
    def outside as Book init tocEntry(sampleBook(), "A", "img/dot.png", 0);
    testing.assertEqual(buildReason($outside), "toc");
}

# NCX entries that point at the same place share a play order, and a heading
# with no target points at its first child.
func testTheNcxSharesPlayOrdersAndPointsHeadingsDown() {
    def b as Book init sampleBook();
    $b = tocEntry($b, "Part", "", 0);
    $b = tocEntry($b, "Intro", "intro.xhtml", 1);
    $b = tocEntry($b, "Two", "text/two.xhtml", 0);
    $b.ncx = true;
    def entries as list of TocEntry init tocOf($b);
    testing.assertEqual(playOrders($entries), [1, 1, 2]);
    testing.assertEqual(firstTarget($entries, 0), "intro.xhtml");
    def data as bytes init build($b);
    def ncx as string init entryOf($data, "OEBPS/toc.ncx");
    testing.assertContains($ncx, '<meta name="dtb:uid" content="' + $b.identifier + '"/>');
    testing.assertContains($ncx, '<meta name="dtb:depth" content="2"/>');
    testing.assertContains($ncx, '<navPoint id="np1" playOrder="1">');
    testing.assertContains($ncx, '<navPoint id="np2" playOrder="1">');
    testing.assertContains($ncx, '<content src="text/two.xhtml"/>');
    def opf as string init entryOf($data, "OEBPS/content.opf");
    testing.assertContains($opf, '<spine toc="ncx">');
    testing.assertContains(
        $opf,
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
}

func testANonLinearChapterIsMarkedInTheSpine() {
    def b as Book init sampleBook();
    $b.chapters[1].linear = false;
    testing.assertContains(contentOpf($b), '<itemref idref="ch2" linear="no"/>');
}

# A read book whose navigation document is in its spine keeps it as a
# chapter with the `nav` property. `build` writes its own nav.xhtml, and a
# package names exactly one, so the chapter loses the property (EPUBCheck
# RSC-005 on a rebuilt Moby-Dick sample before this).
func testOnlyTheWrittenNavigationDocumentIsTheNav() {
    def b as Book init sampleBook();
    $b.chapters[0].properties = "nav svg";
    $b.resources[0].properties = "nav";
    def opf as string init contentOpf($b);
    testing.assertEqual(strings.count($opf, 'properties="nav"'), 1);
    testing.assertContains(
        $opf,
        'href="intro.xhtml" media-type="application/xhtml+xml" properties="svg"');
    testing.assertEqual(withoutProperty("nav", "nav"), "");
    testing.assertEqual(withoutProperty("svg nav mathml", "nav"), "svg mathml");
    testing.assertEqual(withoutProperty("svg", "nav"), "svg");
}

# File names must be unique after case folding (OCF; EPUBCheck OPF-060 on a
# built book with `A.xhtml` and `a.xhtml`), so the builders and `build`
# compare hrefs ignoring case.
func chapterDifferingInCase() {
    chapter(chapter(book("B", "en"), "A.xhtml", "A", "<p>a</p>"), "a.xhtml", "a", "<p>b</p>");
}

func testHrefsDifferingOnlyInCaseClash() {
    testing.assertThrows("chapterDifferingInCase", "epub");
    testing.assertTrue(hrefTaken(book("B", "en"), "Style.CSS"));
    testing.assertTrue(hrefTaken(book("B", "en"), "NAV.xhtml"));
    def b as Book init sampleBook();
    $b.resources[len($b.resources) - 1].href = "INTRO.xhtml";
    testing.assertEqual(buildReason($b), "input");
}

# The deepest table of contents the tiny build writes: it caps `xml`
# nesting at 64, and nav.xhtml holds `html`, `body`, `nav`, `ol`, then an
# `li` and an `ol` per level, then the `li`, the `a` and its text, which
# `xml.encode` counts too.

# A table of contents deeper than nav.xhtml can be read back (the `html`
# parser stops at 256 elements from Jennifer 0.28.0 on, 512 before, two per
# level) is a reached cap. Before the
# cap, level 300 built a book `read` refused and level 600 failed in
# `xml.append` (kind "runtime" then; "limit" since the interpreter's M28.68).
# On the tiny build the interpreter's value nesting cap stops reading
# nav.xhtml back past level 11, so `build` refuses there (TINY_TOC_LEVEL);
# before that cap (jennifer 0.26.0) it wrote levels 12 to 28, which `read`
# then refused.
func testATableOfContentsDeeperThanTheCapIsALimit() {
    def deepest as int init maxTocLevel();
    def b as Book init chapter(book("B", "en"), "c.xhtml", "C", "<p>x</p>");
    for (def i in 0..$deepest + 1) {
        $b = tocEntry($b, "L", "c.xhtml", $i);
    }
    $b.ncx = true;
    def back as Book init read(build($b));
    testing.assertEqual($back.toc, $b.toc);
    $b = tocEntry($b, "L", "c.xhtml", $deepest + 1);
    testing.assertEqual(buildReason($b), "kind:limit");
}

# --- batch builders ----------------------------------------------------------

# `chapters`, `images` and `tocEntries` give the same book as the one-at-a-time
# builders, so the same bytes.
func testBatchBuildersMatchTheSingleOnes() {
    def one as Book init book("Batch", "en");
    $one = markdownChapter($one, "a.xhtml", "A", "# A\n\nText.\n");
    $one = chapter($one, "t/b.xhtml", "B", '<p id="x">B</p>');
    $one = image($one, "img/p.png", bytesOf("png"));
    $one = image($one, "img/q.gif", bytesOf("gif"));
    $one = tocEntry($one, "Part", "", 0);
    $one = tocEntry($one, "A", "a.xhtml", 1);
    $one = tocEntry($one, "B", "t/b.xhtml#x", 1);
    def many as Book init book("Batch", "en");
    $many = chapters(
        $many,
        [
            ChapterSource{href: "a.xhtml", title: "A", body: "# A\n\nText.\n", markdown: true},
            ChapterSource{href: "t/b.xhtml", title: "B", body: '<p id="x">B</p>', markdown: false}
        ]);
    $many = images(
        $many,
        [
            ImageSource{href: "img/p.png", data: bytesOf("png")},
            ImageSource{href: "img/q.gif", data: bytesOf("gif")}
        ]);
    $many = tocEntries(
        $many,
        [
            TocEntry{title: "Part", href: "", level: 0},
            TocEntry{title: "A", href: "a.xhtml", level: 1},
            TocEntry{title: "B", href: "t/b.xhtml#x", level: 1}
        ]);
    testing.assertEqual($many, $one);
    testing.assertEqual(build($many), build($one));
}

func batchWithAClash() {
    chapters(
        book("B", "en"),
        [
            ChapterSource{href: "a.xhtml", title: "A", body: "<p>a</p>", markdown: false},
            ChapterSource{href: "A.xhtml", title: "A", body: "<p>a</p>", markdown: false}
        ]);
}

func batchWithABadImage() {
    images(book("B", "en"), [ImageSource{href: "a.txt", data: bytesOf("x")}]);
}

func batchWithABlankEntry() {
    tocEntries(book("B", "en"), [TocEntry{title: " ", href: "", level: 0}]);
}

# A batch sees the parts it added itself, so two of its own hrefs clash, and
# every item is checked as the single builder checks it.
func testBatchBuildersCheckEveryItem() {
    testing.assertThrows("batchWithAClash", "epub");
    testing.assertThrows("batchWithABadImage", "epub");
    testing.assertThrows("batchWithABlankEntry", "epub");
    def b as Book init chapters(book("B", "en"), []);
    testing.assertEqual(len($b.chapters), 0);
}

# Ids keep counting past ones already taken, whichever builder took them.
func testBatchIdsSkipTakenOnes() {
    def b as Book init chapter(book("B", "en"), "x.xhtml", "X", "<p>x</p>");
    $b.chapters[0].id = "ch2";
    $b = chapters(
        $b,
        [
            ChapterSource{href: "y.xhtml", title: "Y", body: "<p>y</p>", markdown: false},
            ChapterSource{href: "z.xhtml", title: "Z", body: "<p>z</p>", markdown: false}
        ]);
    testing.assertEqual($b.chapters[1].id, "ch3");
    testing.assertEqual($b.chapters[2].id, "ch4");
}

# --- direction ---------------------------------------------------------------

func testTheDirectionIsWrittenAndReadBack() {
    def b as Book init book("Dir", "ar");
    $b.direction = "rtl";
    $b = chapter($b, "c.xhtml", "C", "<p>a</p>");
    testing.assertContains($b.chapters[0].content, 'lang="ar" dir="rtl"');
    $b.toc = tocOf($b);
    def data as bytes init build($b);
    testing.assertContains(entryOf($data, "OEBPS/content.opf"), 'page-progression-direction="rtl"');
    testing.assertContains(entryOf($data, "OEBPS/nav.xhtml"), 'dir="rtl"');
    def back as Book init read($data);
    testing.assertEqual($back.direction, "rtl");
    testing.assertEqual($back, $b);
    def plain as bytes init build(chapter(book("Dir", "en"), "c.xhtml", "C", "<p>a</p>"));
    testing.assertFalse(strings.contains(entryOf($plain, "OEBPS/content.opf"), "page-progression"));
    testing.assertFalse(strings.contains(entryOf($plain, "OEBPS/nav.xhtml"), "dir="));
    $b.direction = "up";
    testing.assertEqual(buildReason($b), "input");
}

# --- landmarks ---------------------------------------------------------------

func testTheLandmarksAreGenerated() {
    def b as Book init book("Marks", "en");
    $b = chapter($b, "cover.xhtml", "Cover", '<section epub:type="cover"><p>c</p></section>');
    $b = chapter($b, "notes.xhtml", "Notes", "<p>n</p>");
    $b.chapters[1].linear = false;
    $b = chapter($b, "one.xhtml", "One", "<p>1</p>");
    def nav as string init navXhtml($b, tocOf($b));
    testing.assertContains(
        $nav,
        '<nav epub:type="landmarks" id="landmarks" hidden="hidden"><ol>' +
            '<li><a epub:type="cover" href="cover.xhtml">Cover</a></li>' +
            '<li><a epub:type="bodymatter" href="one.xhtml">Start</a></li></ol></nav>');
    # Without a cover page, the body starts at the first linear chapter.
    def plain as string init navXhtml(sampleBook(), tocOf(sampleBook()));
    testing.assertFalse(strings.contains($plain, 'epub:type="cover"'));
    testing.assertFalse(strings.contains($plain, '<a epub:type="toc"'));
    testing.assertContains($plain, '<a epub:type="bodymatter" href="intro.xhtml">Start</a>');
    testing.assertEqual(coverPage(sampleBook().chapters), -1);
    # The landmarks are not the table of contents.
    $b.toc = tocOf($b);
    testing.assertEqual(read(build($b)), $b);
}

# --- compression -------------------------------------------------------------

func testACompressedBookIsSmallerAndReadsTheSame() {
    def b as Book init sampleBook();
    $b = markdownChapter(
        $b,
        "long.xhtml",
        "Long",
        strings.replicate("Some words to squeeze. ", 2000));
    $b.toc = tocOf($b);
    def stored as bytes init build($b);
    $b.compress = true;
    def small as bytes init build($b);
    testing.assertTrue(len($small) * 4 < len($stored));
    testing.assertEqual(build($b), $small);
    # mimetype is still first and stored, which `read` checks on the raw bytes.
    testing.assertEqual(binary.readUint("le", $small, 8, 2), 0);
    def back as Book init read($small);
    testing.assertTrue($back.compress);
    testing.assertEqual($back, $b);
    testing.assertFalse(read($stored).compress);
    testing.assertEqual(entryOf($small, "OEBPS/long.xhtml"), $b.chapters[2].content);
    # An entry deflate does not shrink is stored.
    testing.assertEqual(packed(File{name: "x", data: bytesOf("ab")}, true).method, 0);
    testing.assertEqual(
        packed(File{name: "x", data: bytesOf(strings.replicate("ab", 100))}, true).method,
        8);
}

# --- dates, encoded names, read books made writable ---------------------------

# `build` refuses a `dc:date` EPUBCheck would warn about (OPF-053); before,
# "May 2020" was written as given.
func testANonW3cDateIsRefused() {
    def b as Book init sampleBook();
    for (def good in [
        "",
        "2020",
        "2020-05",
        "2020-05-17",
        "2020-05-17T10:30Z",
        "2020-05-17T10:30:05.5+02:00"
    ]) {
        $b.date = $good;
        testing.assertEqual(buildReason($b), "");
    }
    for (def bad in [
        "May 2020",
        "2020-13",
        "2020-05-32",
        "2020/05/17",
        "20-05-17",
        "2020-05-17T10Z",
        "2020-05-17 10:30Z"
    ]) {
        $b.date = $bad;
        testing.assertEqual(buildReason($b), "input");
    }
}

# A name beyond ASCII is kept decoded in the Book, written
# as-is (UTF-8, flagged) in the archive, and percent-encoded in the package,
# the navigation document and the NCX; it reads back as the same Book.
func testUnicodeNamesRoundTrip() {
    def b as Book init book("Namen", "de");
    $b = image($b, "bilder/großesBild.png", bytesOf("png"));
    $b = chapter(
        $b,
        "kapitel/ersteÜbung.xhtml",
        "Übung",
        '<p id="a">x <img src="../bilder/gro%C3%9FesBild.png" alt=""/></p>');
    $b = tocEntry($b, "Übung", "kapitel/ersteÜbung.xhtml", 0);
    $b = tocEntry($b, "A", "kapitel/ersteÜbung.xhtml#a", 1);
    $b.ncx = true;
    def data as bytes init build($b);
    def opf as string init entryOf($data, "OEBPS/content.opf");
    testing.assertContains($opf, 'href="kapitel/erste%C3%9Cbung.xhtml"');
    testing.assertContains($opf, 'href="bilder/gro%C3%9FesBild.png"');
    testing.assertContains(
        entryOf($data, "OEBPS/nav.xhtml"),
        'href="kapitel/erste%C3%9Cbung.xhtml#a"');
    testing.assertContains(entryOf($data, "OEBPS/toc.ncx"), 'src="kapitel/erste%C3%9Cbung.xhtml"');
    testing.assertEqual(entryOf($data, "OEBPS/kapitel/ersteÜbung.xhtml"), $b.chapters[0].content);
    testing.assertEqual(check($b), []);
    testing.assertEqual(read($data), $b);
}

# A read book with its navigation document in the spine as `nav.xhtml`, id
# `nav`, is written with that document as an ordinary chapter, renamed
# `nav-old.xhtml` / `nav-old1`, and its table of contents entries follow it.
# Before, `build` refused the book as using the href twice.
func testANavigationDocumentInTheSpineIsRenamed() {
    def b as Book init sampleBook();
    $b = chapter(
        $b,
        "contents.xhtml",
        "Contents",
        '<nav epub:type="toc"><ol><li><a href="intro.xhtml">Intro</a></li></ol></nav>');
    $b.chapters[2].href = "nav.xhtml";
    $b.chapters[2].id = "nav";
    $b.chapters[2].properties = "nav";
    $b = tocEntry($b, "Contents", "nav.xhtml", 0);
    $b = tocEntry($b, "Intro", "intro.xhtml", 0);
    def back as Book init read(build($b));
    testing.assertEqual(len($back.chapters), 3);
    testing.assertEqual($back.chapters[2].href, "nav-old.xhtml");
    testing.assertEqual($back.chapters[2].id, "nav-old1");
    testing.assertEqual($back.chapters[2].content, $b.chapters[2].content);
    testing.assertEqual($back.toc[0].href, "nav-old.xhtml");
    testing.assertEqual($back.toc[1].href, "intro.xhtml");
}

# A picture in the spine (a chapter without content, its bytes a resource)
# is written as a generated XHTML page beside it that shows it. Before,
# `build` refused the href used twice.
func testAPictureInTheSpineIsWrappedInAPage() {
    def b as Book init book("Comic", "ja");
    $b = image($b, "img/p1.jpg", bytesOf("jpg"));
    $b.chapters[] = Chapter{
        id: "p1",
        href: "img/p1.jpg",
        title: "",
        mediaType: "image/jpeg",
        properties: "",
        content: "",
        linear: true,
        wellFormed: false,
        spineProperties: "",
        mediaOverlay: ""
    };
    $b.resources[1].id = "p1";
    $b = tocEntry($b, "Page 1", "img/p1.jpg", 0);
    def data as bytes init build($b);
    testing.assertContains(entryOf($data, "OEBPS/content.opf"), '<itemref idref="p1-page"/>');
    def back as Book init read($data);
    testing.assertEqual($back.chapters[0].href, "img/p1.xhtml");
    testing.assertContains($back.chapters[0].content, '<img src="p1.jpg" alt="Comic"/>');
    testing.assertEqual($back.toc[0].href, "img/p1.xhtml");
    testing.assertEqual(resource($back, "img/p1.jpg").data, bytesOf("jpg"));
    testing.assertEqual(check($back), []);
    $b.resources = [$b.resources[0]];
    testing.assertEqual(buildReason($b), "input");
}

# --- round 5: spaces, rename, dates, rendition, landmarks, pages -------------

# A read book may have spaces in its names; `build` refuses them (a space
# draws EPUBCheck PKG-010), and `rename` gives the book names it takes,
# rewriting the links, the table of contents, the landmarks, the pages and
# the cover.
func testRenameMakesABookWithSpacesBuildable() {
    def b as Book init book("Spaces", "en");
    $b = image($b, "img/a.png", bytesOf("png"));
    $b = cover($b, "img/c.png", bytesOf("png"));
    $b = chapter(
        $b,
        "one.xhtml",
        "One",
        '<p id="o"><a href="t/two.xhtml#x">on</a> <img src="img/a.png" alt=""/></p>');
    $b = chapter(
        $b,
        "t/two.xhtml",
        "Two",
        '<p id="x"><a href="../one.xhtml#o">back</a> <a href="#x">self</a></p>');
    $b = tocEntry($b, "One", "one.xhtml", 0);
    $b = tocEntry($b, "Two", "t/two.xhtml#x", 0);
    $b.landmarks = [Landmark{type: "bodymatter", title: "Go", href: "t/two.xhtml"}];
    $b.pages = [PageTarget{label: "1", href: "t/two.xhtml#x"}];
    # What `read` gives for a book whose names have spaces.
    $b.chapters[1].href = "t/two 2.xhtml";
    $b.chapters[0].content = strings.replace(
        $b.chapters[0].content,
        "t/two.xhtml#x",
        "t/two%202.xhtml#x");
    $b.resources[2].href = "img/c 1.png";
    $b.cover = "img/c 1.png";
    $b.toc[1].href = "t/two 2.xhtml#x";
    $b.landmarks[0].href = "t/two 2.xhtml";
    $b.pages[0].href = "t/two 2.xhtml#x";
    testing.assertEqual(check($b), []);
    testing.assertEqual(buildReason($b), "input");
    $b = rename($b, "t/two 2.xhtml", "two.xhtml");
    $b = rename($b, "img/c 1.png", "img/c1.png");
    testing.assertEqual(buildReason($b), "");
    testing.assertEqual(check($b), []);
    testing.assertContains($b.chapters[0].content, '<a href="two.xhtml#x">on</a>');
    testing.assertContains(
        $b.chapters[1].content,
        '<a href="one.xhtml#o">back</a> <a href="#x">self</a>');
    testing.assertContains($b.chapters[1].content, 'href="style.css"');
    testing.assertEqual($b.toc[1].href, "two.xhtml#x");
    testing.assertEqual($b.landmarks[0].href, "two.xhtml");
    testing.assertEqual($b.pages[0].href, "two.xhtml#x");
    testing.assertEqual($b.cover, "img/c1.png");
    testing.assertEqual(relativeUrl("a/b/c.xhtml", "a/d e.png"), "../d%20e.png");
}

func renameMissing() {
    rename(sampleBook(), "nope.xhtml", "x.xhtml");
}

func renameOntoAnother() {
    rename(sampleBook(), "intro.xhtml", "TEXT/two.xhtml");
}

# A rename needs a file to rename and a free, valid new name; what it cannot
# see (a link already broken) `check` still reports.
func testRenameRefusesWhatItCannotDo() {
    testing.assertThrows("renameMissing", "epub");
    testing.assertThrows("renameOntoAnother", "epub");
    def b as Book init chapter(
        sampleBook(),
        "three.xhtml",
        "Three",
        '<p><a href="gone.xhtml">x</a></p>');
    $b = rename($b, "three.xhtml", "3.xhtml");
    testing.assertEqual(len(check($b)), 1);
    testing.assertContains(check($b)[0], '3.xhtml: link "gone.xhtml"');
}

# The refusal of a non-W3C date says how to get past it.
func testTheDateErrorSaysToFixOrClearIt() {
    def b as Book init sampleBook();
    $b.date = "May 2020";
    try {
        build($b);
    } catch (e) {
        testing.assertContains($e.message, 'fix it, or clear it with $b.date = ""');
    }
    testing.assertEqual(buildReason($b), "input");
}

# A fixed-layout book: the package rendition metadata, the itemref
# properties and the viewport its pages take are written and read back; a
# value out of its set is refused.
func testRenditionIsWrittenAndReadBack() {
    def b as Book init book("Fixed", "ja");
    $b.layout = "pre-paginated";
    $b.orientation = "portrait";
    $b.spread = "landscape";
    $b.flow = "paginated";
    $b.viewport = "width=1200, height=1600";
    $b = chapter($b, "p1.xhtml", "1", "<p>1</p>");
    $b = chapter($b, "p2.xhtml", "2", "<p>2</p>");
    $b.chapters[0].spineProperties = "page-spread-right";
    $b.chapters[1].spineProperties = "page-spread-left rendition:layout-pre-paginated";
    testing.assertContains(
        $b.chapters[0].content,
        '<meta name="viewport" content="width=1200, height=1600"/>');
    def opf as string init contentOpf($b);
    testing.assertContains($opf, '<meta property="rendition:layout">pre-paginated</meta>');
    testing.assertContains($opf, '<meta property="rendition:spread">landscape</meta>');
    testing.assertContains(
        $opf,
        '<itemref idref="ch2" properties="page-spread-left rendition:layout-pre-paginated"/>');
    $b.toc = tocOf($b);
    testing.assertEqual(read(build($b)), $b);
    $b.layout = "fixed";
    testing.assertEqual(buildReason($b), "input");
}

# A picture page of a fixed-layout book carries the picture's size as its
# viewport, read from a PNG, GIF or JPEG header.
func testAPicturePageTakesThePicturesSize() {
    def png as bytes init encoding.fromText(
        "hex",
        "89504e470d0a1a0a0000000d49484452000002580000031f");
    testing.assertEqual(pictureSize($png), [600, 799]);
    testing.assertEqual(
        pictureSize(binary.concat(bytesOf("GIF89a"), encoding.fromText("hex", "40011e00"))),
        [320, 30]);
    def jpeg as bytes init encoding.fromText("hex", "ffd8ffe000044a46ffc0000b08012c00c8");
    testing.assertEqual(pictureSize($jpeg), [200, 300]);
    testing.assertEqual(pictureSize(bytesOf("RIFF....WEBP")), []);
    def b as Book init book("Comic", "ja");
    $b.layout = "pre-paginated";
    $b = image($b, "p.png", $png);
    $b.chapters[] = Chapter{
        id: "res2",
        href: "p.png",
        title: "",
        mediaType: "image/png",
        properties: "",
        content: "",
        linear: true,
        wellFormed: false,
        spineProperties: "page-spread-right",
        mediaOverlay: ""
    };
    def back as Book init read(build($b));
    testing.assertContains(
        $back.chapters[0].content,
        '<meta name="viewport" content="width=600, height=799"/>');
    testing.assertEqual($back.chapters[0].spineProperties, "page-spread-right");
}

# The book's own landmarks and page list are written; the generated
# landmarks read back as none, so a book that has none reads back equal.
func testLandmarksAndPagesAreWrittenAndReadBack() {
    def b as Book init sampleBook();
    $b.toc = tocOf($b);
    testing.assertEqual(read(build($b)).landmarks, []);
    $b.landmarks = [
        Landmark{type: "bodymatter", title: "Go", href: "text/two.xhtml"},
        Landmark{type: "cover", title: "Pic", href: "img/dot.png"}
    ];
    $b.pages = [
        PageTarget{label: "1", href: "intro.xhtml"},
        PageTarget{label: "2", href: "text/two.xhtml#t"}
    ];
    def nav as string init entryOf(build($b), "OEBPS/nav.xhtml");
    testing.assertContains(
        $nav,
        '<li><a epub:type="bodymatter" href="text/two.xhtml">Go</a></li></ol></nav>');
    testing.assertContains(
        $nav,
        '<nav epub:type="page-list" id="page-list" hidden="hidden"><ol><li><a href="intro.xhtml">1</a>');
    testing.assertEqual(
        check($b),
        ['landmark "cover": "img/dot.png" is not in a chapter; build leaves it out']);
    $b.landmarks = [$b.landmarks[0]];
    testing.assertEqual(read(build($b)), $b);
}

# Manifest ids are XML names, which take letters of any script; before,
# `build` refused a read book's id "表紙" (the kusamakura sample).
func testIdsMayBeUnicodeXmlNames() {
    def b as Book init sampleBook();
    $b.chapters[0].id = "表紙";
    testing.assertEqual(buildReason($b), "");
    $b.chapters[0].id = "1st";
    testing.assertEqual(buildReason($b), "input");
}

# --- round 6: rebuild conversions, cover pages, media overlays ---------------

def const XHTML11 as string init '<?xml version="1.0" encoding="utf-8"?>' +
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">' +
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>' +
    '<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"/>' +
    '<meta content="text/css" http-equiv="Content-Style-Type"/><title>Old</title></head>' +
    '<body><table summary="A table" class="t"><tr><td>1</td></tr></table><p>Text.</p></body></html>';

# An EPUB 2 chapter is written as HTML5: the HTML5 doctype, without the
# `<meta http-equiv>` and the table `summary` HTML5 forbids; the text is the
# same, and a note says what was dropped. Before, it was written as it was
# (EPUBCheck HTM-004 and RSC-005).
func testAnXhtml11ChapterIsWrittenAsHtml5() {
    def b as Book init sampleBook();
    $b.chapters[0].content = XHTML11;
    def w as Book init writable($b);
    def page as string init $w.chapters[0].content;
    testing.assertContains($page, "<!DOCTYPE html><html");
    testing.assertFalse(strings.contains($page, "http-equiv"));
    testing.assertFalse(strings.contains($page, "summary"));
    testing.assertContains($page, '<table class="t">');
    testing.assertEqual(text($w.chapters[0]), text($b.chapters[0]));
    testing.assertEqual(
        $w.notes,
        [
            'chapter "intro.xhtml" is XHTML 1.1; written as HTML5, dropping 2 <meta http-equiv> and 1 table summary'
        ]);
    testing.assertEqual(entryOf(build($b), "OEBPS/intro.xhtml"), $page);
    # A page the builders made is left alone.
    testing.assertEqual(writable(sampleBook()), sampleBook());
}

# `writable` leaves out a table of contents heading with nothing under it
# (a nested one first), with a note; `build` still refuses one.
func testWritableDropsEmptyTocHeadings() {
    def b as Book init sampleBook();
    $b = tocEntries(
        $b,
        [
            TocEntry{title: "Intro", href: "intro.xhtml", level: 0},
            TocEntry{title: "Empty", href: "", level: 0},
            TocEntry{title: "Inner", href: "", level: 1},
            TocEntry{title: "Two", href: "text/two.xhtml", level: 0}
        ]);
    testing.assertEqual(buildReason($b), "toc");
    def w as Book init writable($b);
    testing.assertEqual(len($w.toc), 2);
    testing.assertEqual(
        $w.notes,
        [
            'table of contents heading "Inner" has nothing under it; left out',
            'table of contents heading "Empty" has nothing under it; left out'
        ]);
    testing.assertEqual(buildReason($w), "");
}

# The cover may be a chapter: an SVG page carries `cover-image`, and both an
# SVG and an XHTML page are named by `<meta name="cover">` and the cover
# landmark; it reads back as the cover. Before, `build` refused a cover that
# was not an image file.
func testTheCoverMayBeAPage() {
    def b as Book init sampleBook();
    $b = chapter($b, "cover.xhtml", "Cover", "<p>A cover</p>");
    $b.cover = "cover.xhtml";
    $b.toc = tocOf($b);
    def opf as string init contentOpf($b);
    testing.assertContains($opf, '<meta name="cover" content="ch3"/>');
    testing.assertFalse(strings.contains($opf, "cover-image"));
    testing.assertContains(
        navXhtml($b, $b.toc),
        '<a epub:type="cover" href="cover.xhtml">Cover</a>');
    testing.assertEqual(read(build($b)), $b);
    def svg as Book init sampleBook();
    $svg.chapters[] = Chapter{
        id: "c",
        href: "cover.svg",
        title: "",
        mediaType: "image/svg+xml",
        properties: "",
        content: '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>',
        linear: true,
        wellFormed: true,
        spineProperties: "",
        mediaOverlay: ""
    };
    $svg.cover = "cover.svg";
    testing.assertContains(
        contentOpf($svg),
        'href="cover.svg" media-type="image/svg+xml" properties="cover-image"');
    testing.assertEqual(read(build($svg)).cover, "cover.svg");
    $svg.cover = "nowhere.png";
    testing.assertEqual(buildReason($svg), "input");
}

# Media overlays pass through: each chapter's `media-overlay`, the SMIL and
# audio files among the resources, the `media:` metadata. A media overlay
# that names no SMIL file is refused.
func testMediaOverlaysAreWrittenBack() {
    def b as Book init sampleBook();
    $b = file($b, "mo/intro.smil", "application/smil+xml", bytesOf("<smil/>"));
    $b = file($b, "audio/intro.mp3", "audio/mpeg", bytesOf("mp3"));
    $b.chapters[0].mediaOverlay = $b.resources[2].id;
    $b.mediaMeta = [
        Meta{property: "media:duration", refines: "#" + $b.resources[2].id, value: "0:00:10"},
        Meta{property: "media:duration", refines: "", value: "0:00:10"},
        Meta{property: "media:active-class", refines: "", value: "-epub-media-overlay-active"}
    ];
    def opf as string init contentOpf($b);
    testing.assertContains(
        $opf,
        'href="intro.xhtml" media-type="application/xhtml+xml" media-overlay="res3"');
    testing.assertContains($opf, '<meta property="media:duration" refines="#res3">0:00:10</meta>');
    testing.assertContains(
        $opf,
        '<meta property="media:active-class">-epub-media-overlay-active</meta>');
    $b.toc = tocOf($b);
    testing.assertEqual(read(build($b)), $b);
    $b.chapters[0].mediaOverlay = "res4";
    testing.assertEqual(buildReason($b), "input");
}
