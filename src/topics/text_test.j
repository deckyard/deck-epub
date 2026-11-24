# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# epub - white-box tests for plain text and the HTML reading: entities, the
# `html` fallback for chapters that are not XML, and the agreement of the two
# ways a chapter is read. Spliced into epub_test.j via include.

func chapterFrom(content as string, wellFormed as bool) {
    return Chapter{
        id: "c",
        href: "c.xhtml",
        title: "",
        mediaType: XHTML_TYPE,
        properties: "",
        content: $content,
        linear: true,
        wellFormed: $wellFormed,
        spineProperties: "",
        mediaOverlay: ""
    };
}

# The text of a document both ways: tokenized as XML and parsed as HTML.
func bothWays(content as string) {
    return [text(chapterFrom($content, true)), text(chapterFrom($content, false))];
}

func testCharacterReferencesAreDecoded() {
    testing.assertEqual(len(LATIN1), 96);
    testing.assertEqual(entityFor("nbsp"), "\u00A0");
    testing.assertEqual(entityFor("not"), "\u00AC");
    testing.assertEqual(entityFor("yuml"), "\u00FF");
    testing.assertEqual(entityFor("mdash"), "\u2014");
    testing.assertEqual(entityFor("Omega"), "\u03A9");
    testing.assertEqual(entityFor("quot"), '"');
    testing.assertEqual(entityFor("#233"), "\u00E9");
    testing.assertEqual(entityFor("#x1F600"), "\U0001F600");
    testing.assertEqual(entityFor("#X41"), "A");
    # The markup three stay references for the `html` parser.
    testing.assertEqual(entityFor("amp"), "&amp;");
    testing.assertEqual(entityFor("#60"), "&lt;");
    testing.assertEqual(entityFor("#x26"), "&amp;");
    testing.assertEqual(entityFor("#62"), "&gt;");
    testing.assertEqual(entityFor("#0"), "\uFFFD");
    testing.assertEqual(entityFor("#xD800"), "\uFFFD");
    testing.assertEqual(entityFor("#x110000"), "\uFFFD");
    testing.assertEqual(entityFor("bogus"), "&amp;bogus;");
}

func testEntitiesAreDecodedInOnePass() {
    testing.assertEqual(decodeEntities("a&nbsp;b"), "a\u00A0b");
    testing.assertEqual(decodeEntities("&amp;nbsp; &lt;p&gt;"), "&amp;nbsp; &lt;p&gt;");
    testing.assertEqual(decodeEntities("no refs"), "no refs");
    testing.assertEqual(decodeEntities("& alone &;"), "& alone &;");
    testing.assertEqual(html.unescape(decodeEntities("&amp;nbsp;&hellip;&#38;")), "&nbsp;\u2026&");
}

# The milestone's case: HTML entities and unclosed tags. The `xml` parser
# refuses the chapter, so it is read as HTML.
def const TAG_SOUP as string init '<html><head><title>Soup &amp; Bread</title>' +
    '<style>p { color: red; }</style></head><body>' +
    '<h1>Chapter&nbsp;One</h1><p>First<br>line<p>Second &mdash; with <b>bold' +
    '<p>Caf&eacute; &copy; 1900 &unknown; &lt;b&gt;' +
    '<ul><li>one<li>two</ul><script>var x = "<p>no</p>";</script>' +
    '</body></html>';

func testATagSoupChapterFallsBackToHtml() {
    def b as Book init read(minimalBook(TAG_SOUP, []));
    def c as Chapter init $b.chapters[0];
    testing.assertFalse($c.wellFormed);
    testing.assertEqual($c.content, TAG_SOUP);
    testing.assertEqual($c.title, "Soup & Bread");
    testing.assertEqual(
        text($c),
        "Chapter\u00A0One\n\nFirst\nline\n\nSecond \u2014 with bold\n\n" +
            "Caf\u00E9 \u00A9 1900 &unknown; <b>\n\none\n\ntwo");
}

func testAWellFormedChapterIsTokenized() {
    def b as Book init read(minimalBook(PAGE, []));
    testing.assertTrue($b.chapters[0].wellFormed);
    testing.assertEqual(text($b.chapters[0]), "Hello.");
}

def const FULL_PAGE as string init '<?xml version="1.0" encoding="utf-8"?>' +
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">' +
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>' +
    '<style type="text/css">/*<![CDATA[*/ p > a { } /*]]>*/</style></head>' +
    '<body class="x"><!-- a comment <p>hidden</p> -->' +
    '<h2 title="a > b">Heading</h2>' +
    "<p>Text   spread\n  over\tlines, <em>emphasis</em>, <a href=\"#x\">a link</a>.</p>" +
    "<pre>  keep\n    this\n</pre>" +
    '<div><p>nested <span>inline</span></p>tail</div>' +
    '<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>' +
    '<p>x<br/>y<br />z</p><p><![CDATA[a <raw> section]]></p>' +
    '<p>&lt;not a tag&gt; &amp;amp; &#8212;</p><hr/><p/><p>end</p>' +
    '</body></html>';

func testPlainTextKeepsParagraphsBreaksAndPre() {
    testing.assertEqual(
        text(chapterFrom(FULL_PAGE, true)),
        "Heading\n\n" +
            "Text spread over lines, emphasis, a link.\n\n" +
            "  keep\n    this\n\n" +
            "nested inline\n\ntail\n\nA B\n\n1 2\n\nx\ny\nz\n\na <raw> section\n\n" +
            "<not a tag> &amp; \u2014\n\nend");
}

# Both readings give the same text for a well-formed document: the token
# walk is the fast path, the `html` tree the reference.
func testTheTwoReadingsAgree() {
    def same as list of string init bothWays(FULL_PAGE);
    testing.assertEqual($same[0], $same[1]);
    if (not haveGutenberg()) {
        return;
    }
    def b as Book init gutenberg3();
    for (def c in $b.chapters) {
        def both as list of string init bothWays($c.content);
        testing.assertEqual($both[0], $both[1]);
    }
    for (def c in sampleBook().chapters) {
        def both as list of string init bothWays($c.content);
        testing.assertEqual($both[0], $both[1]);
    }
}

# A document with no body (an SVG chapter) is read whole.
func testADocumentWithoutABodyIsReadWhole() {
    def svg as string init '<svg xmlns="http://www.w3.org/2000/svg"><title>pic</title>' +
        '<text x="1" y="2">Caption</text></svg>';
    def same as list of string init bothWays($svg);
    testing.assertEqual($same[0], "Caption");
    testing.assertEqual($same[1], "Caption");
}

func testInlineTextCollapsesAnElement() {
    def doc as html.Node init parseHtml("<p> a <b>b\n</b>  c </p><p>d</p>");
    def ps as list of html.Node init findTags($doc, "p", []);
    testing.assertEqual(len($ps), 2);
    testing.assertEqual(inlineText($ps[0]), "a b c");
}

func testAnEmptyChapterHasNoText() {
    testing.assertEqual(text(chapterFrom("", false)), "");
    testing.assertEqual(text(chapterFrom("<html><body></body></html>", true)), "");
}

# The tokenizer takes the local name of a prefixed tag and folds its case, so
# `<x:P>` is a paragraph like `<p>`; an inline tag between them is skipped.
func testPrefixedAndUpperCaseTagsAreBlocks() {
    def doc as string init '<x:html xmlns:x="http://www.w3.org/1999/xhtml"><x:body>' +
        '<x:P>a <x:em>b</x:em></x:P><P>c</P><x:Br/></x:body></x:html>';
    testing.assertEqual(text(chapterFrom($doc, true)), "a b\n\nc");
}

# `tokenWalk` skips any tag not in ACTIVE before calling `onOpen` /
# `onClose`, so ACTIVE must hold every tag those act on, and nothing else.
func testTheActiveTagsAreTheOnesTheEventsActOn() {
    def want as list of string init lists.concat(SKIPPED, BLOCKS);
    $want[] = "br";
    $want[] = "td";
    $want[] = "th";
    testing.assertEqual(lists.sort(maps.keys(ACTIVE)), lists.sort($want));
}

# A page of 200 nested elements, far deeper than the tiny build's 120 nested
# calls, is walked with an explicit stack, read as HTML (not well formed) or
# not; before, `walk`, `findTags` and `gatherText` recursed once per level.
# It stays under the `html` parser's nesting cap (256 from Jennifer 0.28.0
# on, 512 before); a page past both is kind "limit". The tiny build's value
# nesting cap (64 levels, two per element) stops the `html` parse of the
# 200-level page first, as kind "limit" too.
func testADeeplyNestedPageIsWalkedWithoutRecursion() {
    testing.assertEqual(parseKind(nestedPage(600)), "limit");
    def deep as string init nestedPage(200);
    if (meta.BUILD == "tinygo") {
        testing.assertEqual(parseKind($deep), "limit");
        return;
    }
    testing.assertEqual(text(chapterFrom($deep, false)), "deep text");
    def doc as html.Node init parseHtml($deep);
    testing.assertEqual(len(findTags($doc, "div", [])), 200);
    testing.assertEqual(inlineText(findTags($doc, "body", [])[0]), "deep text");
}

func nestedPage(depth as int) {
    return "<html><body>" + strings.replicate("<div>", $depth) + "<p>deep <b>text</b></p>" +
        strings.replicate("</div>", $depth) + "</body></html>";
}

# The kind `parseHtml` throws for a page, "" when it parses.
func parseKind(page as string) {
    try {
        parseHtml($page);
    } catch (e) {
        return $e.kind;
    }
    return "";
}

