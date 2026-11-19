# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * epub - read and write EPUB books, in pure Jennifer.
 *
 * An EPUB is a zip of XHTML plus two XML files: `META-INF/container.xml`,
 * which names the package document, and the package document (the OPF), which
 * holds the metadata, the manifest of every file and the spine, the reading
 * order. This deck writes EPUB 3.3 books, with an optional EPUB 2 `toc.ncx` for
 * older readers, and reads EPUB 2 and 3 books into the same `Book`.
 *
 *   write  {@link book} / {@link author} / {@link cover} / {@link chapter} /
 *          {@link markdownChapter} / {@link image} / {@link file} /
 *          {@link stylesheet} / {@link tocEntry} / {@link build}
 *   batch  {@link chapters} / {@link images} / {@link tocEntries}
 *   read   {@link read} / {@link readWith} / {@link readOptions} /
 *          {@link resource} / {@link resolve} / {@link text}
 *   links  {@link check} / {@link rename}
 *   rebuild {@link writable}
 *
 * Builders return the updated book: `$b = epub.chapter($b, ...)`. Writing is
 * deterministic: a fixed timestamp and an identifier derived from the title,
 * so the same book gives the same bytes. Every failure of this deck throws an
 * {@link EpubError} (kind `"epub"`, with a `reason`); a reached cap is kind
 * `"limit"`.
 *
 * The topic files under `topics/` are spliced in with `include`; this file is
 * the module boundary. White-box tests: `epub_test.j`.
 *
 * @module epub
 * @see https://www.w3.org/TR/epub-33/
 * @example
 *   import "@deckyard/epub/" as epub;
 *
 *   def b as epub.Book init epub.book("Notes", "en");
 *   $b = epub.author($b, "Ada Lovelace");
 *   $b = epub.markdownChapter($b, "one.xhtml", "One", "# One\n\nHello.\n");
 *   def data as bytes init epub.build($b);
 *   def back as epub.Book init epub.read($data);
 *   io.printf("%s\n", epub.text($back.chapters[0]));
 */

use strings;
use convert;
use lists;
use maps;
use regex;
use xml;
use crc;
use hash;
use encoding;
use binary;
use meta;
use archive;
use compress;

import "markdown.j" as markdown;
import "html.j" as html;

include "topics/core.j";
include "topics/zip.j";
include "topics/write.j";
include "topics/read.j";
include "topics/text.j";
include "topics/check.j";
