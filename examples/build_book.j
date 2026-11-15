#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * Build a small book: a cover page, two chapters (Markdown and XHTML) added
 * in one batch, a cover, a nested table of contents and an EPUB 2 NCX,
 * deflated. The links are checked before the book is built.
 *
 *   jennifer run examples/build_book.j            # build, read back, report
 *   jennifer run examples/build_book.j out.epub   # and write it to out.epub
 */

use io;
use fs;
use os;
use images;

import "../src/epub.j" as epub;

# A cover drawn here, so the example needs no files.
def cover as bytes init images.encode("png", images.create(60, 90, images.rgb(40, 70, 120)));

def b as epub.Book init epub.book("Field Notes", "en");
$b = epub.author($b, "Ada Lovelace");
$b.description = "Two short chapters, built with @deckyard/epub.";
$b = epub.cover($b, "img/cover.png", $cover);
$b = epub.chapters(
    $b,
    [
        epub.ChapterSource{
            href: "cover.xhtml",
            title: "Cover",
            body: '<section epub:type="cover"><img src="img/cover.png" alt="Field Notes"/></section>',
            markdown: false
        },
        epub.ChapterSource{
            href: "text/one.xhtml",
            title: "Observations",
            body: "# Observations\n\n" +
                "The engine *weaves* algebraic patterns.\n\n" +
                "## Notes\n\n- one\n- two\n\n![The cover](../img/cover.png)\n",
            markdown: true
        },
        epub.ChapterSource{
            href: "text/two.xhtml",
            title: "Conclusions",
            body: '<h1 id="c">Conclusions</h1>' +
                '<p epub:type="epigraph">That brain of mine is something more than merely mortal.</p>',
            markdown: false
        }
    ]);
$b = epub.tocEntries(
    $b,
    [
        epub.TocEntry{title: "Observations", href: "text/one.xhtml", level: 0},
        epub.TocEntry{title: "Conclusions", href: "", level: 0},
        epub.TocEntry{title: "The conclusion", href: "text/two.xhtml#c", level: 1}
    ]);
$b.ncx = true;
$b.compress = true;

for (def w in epub.check($b)) {
    io.printf("warning: %s\n", $w);
}

def data as bytes init epub.build($b);
io.printf("built %d bytes\n", len($data));

def back as epub.Book init epub.read($data);
io.printf(
    "%s by %s, %d chapters, cover %s\n",
    $back.title,
    $back.authors[0],
    len($back.chapters),
    $back.cover);
for (def c in $back.chapters) {
    io.printf("\n## %s\n%s\n", $c.title, epub.text($c));
}

if (len(os.ARGS) > 1) {
    fs.writeBytes(os.ARGS[1], $data);
    io.printf("\nwrote %s\n", os.ARGS[1]);
}
