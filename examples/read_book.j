#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * Print a book's metadata, what `read` tolerated in it (its notes), table of
 * contents, files and the start of each chapter.
 *
 *   jennifer run examples/read_book.j book.epub
 *
 * Without an argument it reads a book it builds itself, so it runs anywhere.
 */

use io;
use fs;
use os;
use strings;

import "../src/epub.j" as epub;

func sample() {
    def d as epub.Book init epub.book("A Sampler", "en");
    $d = epub.author($d, "Anonymous");
    $d = epub.markdownChapter($d, "one.xhtml", "First", "# First\n\nThe *first* chapter.\n");
    $d = epub.markdownChapter($d, "two.xhtml", "Second", "# Second\n\nThe second, with `code`.\n");
    return epub.build($d);
}

# The start of a text, on one line.
func cut(s as string, n as int) {
    def line as string init strings.replace($s, "\n", " ");
    if (len($line) > $n) {
        return $line[..$n] + "...";
    }
    return $line;
}

def data as bytes;
if (len(os.ARGS) > 1) {
    $data = fs.readBytes(os.ARGS[1]);
} else {
    $data = sample();
}

try {
    def b as epub.Book init epub.read($data);
    io.printf("%s (EPUB %s, %s)\n", $b.title, $b.version, $b.lang);
    for (def a in $b.authors) {
        io.printf("  by %s\n", $a);
    }
    io.printf("  identifier %s\n", $b.identifier);
    for (def n in $b.notes) {
        io.printf("  note: %s\n", $n);
    }
    if ($b.cover != "") {
        io.printf("  cover %s, %d bytes\n", $b.cover, len(epub.resource($b, $b.cover).data));
    }
    io.printf("\ncontents\n");
    for (def e in $b.toc) {
        io.printf("  %s%s\n", strings.repeat("  ", $e.level), $e.title);
    }
    io.printf("\nfiles\n");
    for (def r in $b.resources) {
        io.printf("  %s (%s, %d bytes)\n", $r.href, $r.mediaType, len($r.data));
    }
    io.printf("\nchapters\n");
    for (def c in $b.chapters) {
        io.printf("  [%s] %s: %s\n", $c.href, $c.title, cut(epub.text($c), 70));
    }
} catch (e) {
    if ($e.kind == "epub" and $e.reason == "drm") {
        io.eprintf("cannot read: the book is DRM-protected\n");
        exit 1;
    }
    io.eprintf("cannot read: %s\n", $e.message);
    exit 1;
}
