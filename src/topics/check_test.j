# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# epub - white-box tests for `check`. Spliced into epub_test.j via include.

# A book whose links all resolve: chapter to chapter (in a directory and
# back), to a fragment, to a picture, to the stylesheet; remote and mailto
# links are not followed.
func linkedBook() {
    def b as Book init book("Links", "en");
    $b = image($b, "img/a.png", bytesOf("png"));
    $b = chapter(
        $b,
        "one.xhtml",
        "One",
        '<h1 id="top">One</h1><p><a href="text/two.xhtml#end">on</a> <img src="img/a.png" alt=""/>' +
            '<a href="https://example.org/x.html">web</a> <a href="mailto:a@b.c">mail</a>' +
            '<a href="#top">up</a></p>');
    $b = chapter(
        $b,
        "text/two.xhtml",
        "Two",
        "<p id='end'><a href='../one.xhtml'>back</a> <a href=\"../nav.xhtml\">contents</a></p>");
    $b = tocEntry($b, "One", "one.xhtml#top", 0);
    $b = tocEntry($b, "Two", "text/two.xhtml", 0);
    return $b;
}

func testABookWhoseLinksResolveHasNoWarnings() {
    testing.assertEqual(check(linkedBook()), []);
}

func testBrokenLinksAreWarnedAbout() {
    def b as Book init linkedBook();
    $b = chapter(
        $b,
        "three.xhtml",
        "Three",
        '<p><a href="one.xhtml#nowhere">a</a> <img src="img/b.png" alt=""/> ' +
            '<a href="gone.xhtml">b</a> <a href="#self">c</a> <a href="a%zz.xhtml">d</a></p>');
    $b = tocEntry($b, "Lost", "text/two.xhtml#lost", 1);
    def w as list of string init check($b);
    testing.assertEqual(len($w), 6);
    testing.assertContains($w[0], 'three.xhtml: link "one.xhtml#nowhere" points at "#nowhere"');
    testing.assertContains($w[1], '"img/b.png", which is not in the book');
    testing.assertContains($w[2], '"gone.xhtml", which is not in the book');
    testing.assertContains($w[3], '"#self", which is no id in "three.xhtml"');
    testing.assertContains($w[4], "bad percent escape");
    testing.assertContains($w[5], 'table of contents entry "Lost": link "text/two.xhtml#lost"');
    # `build` is unchanged: the book is valid EPUB all the same.
    testing.assertEqual(buildReason($b), "");
}

# A read book's hrefs are percent-decoded, and so are its links; an
# attribute's references are decoded before it is resolved.
func testLinksAreDecodedBeforeTheyAreResolved() {
    def b as Book init book("Links", "en");
    $b = chapter($b, "one.xhtml", "One", '<p id="a&amp;b"><a href="one.xhtml#a&amp;b">x</a></p>');
    $b.chapters[0].href = "a b.xhtml";
    $b.chapters[0].content = strings.replace($b.chapters[0].content, "one.xhtml#", "a%20b.xhtml#");
    testing.assertEqual(check($b), []);
}

# A chapter added before `direction` was set has no `dir` on its page.
func testAChapterWithoutTheBooksDirectionIsWarnedAbout() {
    def b as Book init book("Dir", "ar");
    $b = chapter($b, "early.xhtml", "Early", "<p>a</p>");
    $b.direction = "rtl";
    $b = chapter($b, "late.xhtml", "Late", "<p>b</p>");
    def w as list of string init check($b);
    testing.assertEqual(len($w), 1);
    testing.assertContains($w[0], "early.xhtml: the page is not marked dir=");
}
