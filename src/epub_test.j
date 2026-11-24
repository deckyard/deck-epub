# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests for the epub module: jennifer test src/epub_test.j
 *
 * One test file per topic under `topics/`, spliced with `include` in the
 * order `epub.j` splices the topics. The real-world books (Project Gutenberg)
 * are embedded in `topics/fixtures/`, so the overlays also run from a copy of
 * `src/` alone, as `jvc` runs them.
 */

use testing;
use meta;
use fs;

include "topics/core_test.j";
include "topics/zip_test.j";
include "topics/write_test.j";
include "topics/read_test.j";
include "topics/text_test.j";
include "topics/check_test.j";
