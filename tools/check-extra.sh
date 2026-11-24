#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# The deck's own check: validate a book the deck builds with EPUBCheck, the
# reference EPUB validator (https://github.com/w3c/epubcheck, Java).
#
# Optional: it runs only when Docker works and EPUBCHECK_JAR names
# epubcheck.jar from an unpacked EPUBCheck release (its lib/ beside it), and
# skips otherwise, so CI passes without it. The jar runs in a throwaway
# container (EPUBCHECK_IMAGE, default eclipse-temurin:21-jre), removed after.
# Warnings fail the check as well as errors.
#
# The book is examples/build_book.j's: a cover and a cover page (so the
# landmarks name one), Markdown and XHTML chapters in a subdirectory added in
# one batch, epub:type, a nested table of contents with a heading, an EPUB 2
# toc.ncx, every entry but mimetype deflated.
#
# Usage: EPUBCHECK_JAR=/path/to/epubcheck.jar tools/check-extra.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The Project Gutenberg overlays return early without testdata/gutenberg/
# (where the overlays run from a copy of src/ alone); here, in the gate, the
# files must be present, or those tests would pass without running.
for f in testdata/gutenberg/pg1080-epub3.epub testdata/gutenberg/pg1080-epub2.epub; do
    if [[ ! -s "$f" ]]; then
        echo "check-extra: $f is missing; run tools/build-fixtures.sh" >&2
        exit 1
    fi
done

JENNIFER="${JENNIFER:-jennifer}"
jar="${EPUBCHECK_JAR:-}"
image="${EPUBCHECK_IMAGE:-eclipse-temurin:21-jre}"

if [[ -z "$jar" || ! -f "$jar" ]]; then
    echo "epubcheck: skipped (set EPUBCHECK_JAR to an epubcheck.jar to run it)"
    exit 0
fi
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "epubcheck: skipped (no working docker)"
    exit 0
fi

# Inside the checkout: CI's interpreter is a container that mounts only it.
out=.ci-fixtures
mkdir -p "$out"
trap 'rm -f "$out/epubcheck.epub"; rmdir "$out" 2>/dev/null || true' EXIT
$JENNIFER run examples/build_book.j "$out/epubcheck.epub" >/dev/null

jardir="$(cd "$(dirname "$jar")" && pwd)"
docker run --rm \
    -v "$PWD/$out:/books:ro" \
    -v "$jardir:/epubcheck:ro" \
    "$image" java -jar "/epubcheck/$(basename "$jar")" --failonwarnings /books/epubcheck.epub
echo "epubcheck: the built book is valid"
