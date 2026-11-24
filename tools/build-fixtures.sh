#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Downloads the Project Gutenberg fixtures into testdata/gutenberg/: eBook
# #1080, Jonathan Swift, "A Modest Proposal" (public domain),
# https://www.gutenberg.org/ebooks/1080, in its EPUB 3 (with images) and
# older EPUB 2 (without images) files, fetched from the Project Gutenberg
# mirror gutenberg.pglaf.org (gutenberg.org refuses scripted downloads and
# asks robots to use a mirror). The files are kept exactly as
# Project Gutenberg serves them, with its licence inside, and stay outside
# src/: consumers never vendor them, and the overlays that read them return
# early where testdata/ is missing (jvc publish, jvc install --runtests).
#
# Needs curl and network access; not run in CI. Project Gutenberg regenerates
# its files from time to time, so a rerun may change what the overlays see.
#
# Usage: tools/build-fixtures.sh
set -euo pipefail
cd "$(dirname "$0")/.."
dir=testdata/gutenberg
mirror=https://gutenberg.pglaf.org/cache/epub/1080
mkdir -p "$dir"
curl -fsSL -o "$dir/pg1080-epub3.epub" "$mirror/pg1080-images-3.epub"
curl -fsSL -o "$dir/pg1080-epub2.epub" "$mirror/pg1080.epub"
ls -l "$dir"/*.epub
