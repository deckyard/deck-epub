# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# epub - `check`: the links inside a book that lead nowhere; `rename`, which
# moves a file and the links to it. `build` only
# refuses what makes the package invalid; a broken `<a href>` or `<img src>`
# is valid EPUB that a reader shows as a dead link or a missing picture, so it
# is reported here, as warnings, rather than refused.

# An `href`, `src` or `xlink:href` attribute, its value in group 2 or 3.
def const LINK_ATTR as string init '\s(?:xlink:)?(?:href|src)\s*=\s*(?:"([^"]*)"|' + "'([^']*)')";

# An `id` attribute, its value in group 1 or 2.
def const ID_ATTR as string init '\sid\s*=\s*(?:"([^"]*)"|' + "'([^']*)')";

# The value of an attribute matched by LINK_ATTR or ID_ATTR, references
# decoded (`&amp;` in a query, `&#x41;`).
func attrText(m as regex.Match) {
    def raw as string init $m.groups[0];
    if ($raw == "" and $m.groups[1] != "") {
        $raw = $m.groups[1];
    }
    return pieceText($raw);
}

# Every element id of a document.
func idsOf(content as string) {
    def out as map of string to bool;
    for (def m in regex.findAll(ID_ATTR, $content)) {
        $out[attrText($m)] = true;
    }
    return $out;
}

# The files of a book and the ids of each chapter. A struct, so `linkWarning`
# borrows it: a nested map passed bare is copied on every call.
def struct Targets {
    files as map of string to bool,
    ids as map of string to map of string to bool
};

# The warning for one link written in `from`, "" when it resolves: its file
# must be in the book (`build`'s navigation document counts), and a fragment
# into a chapter must name an id in it.
func linkWarning(from as string, link as string, t as Targets) {
    def target as string init "";
    try {
        $target = resolveIn($from, $link);
    } catch (e) {
        if ($e.kind != ERROR_KIND) {
            throw $e;
        }
        return $from + ": link " + shown($link) + " has a bad percent escape";
    }
    def parts as list of string init splitFragment($target);
    if (not maps.has($t.files, $parts[0])) {
        return $from + ": link " + shown($link) + " points at " + shown($parts[0]) +
            ", which is not in the book";
    }
    if (len($parts[1]) > 1 and maps.has($t.ids, $parts[0]) and
        not maps.has($t.ids[$parts[0]], $parts[1][1..])) {
        return $from + ": link " + shown($link) + " points at " + shown($parts[1]) +
            ", which is no id in " + shown($parts[0]);
    }
    return "";
}

/**
 * The links in a book that lead nowhere, as warnings: an `href` or `src` (or
 * `xlink:href`) in a chapter, and a table of contents entry, whose file is
 * not in the book, or whose `#fragment` names no element id in the chapter
 * it points into. URLs with a scheme (`https:`, `mailto:`, `data:`) are not
 * checked. A chapter written in another direction than `direction` (no
 * `dir` on its `<html>`, as when it was added before `direction` was set)
 * is reported too. `build` does not call it: a book with warnings is still a
 * valid EPUB.
 *
 * @param b {Book} the book
 * @return {list of string} one warning per problem, chapters in reading
 *   order, links in document order, then the table of contents; empty when
 *   every link resolves
 * @example
 *   for (def w in epub.check($b)) {
 *       io.eprintf("warning: %s\n", $w);
 *   }
 */
export func check(b as Book) {
    def files as map of string to bool init {NAV_HREF: true};
    if ($b.ncx) {
        $files[NCX_HREF] = true;
    }
    def ids as map of string to map of string to bool;
    for (def i in 0..len($b.chapters)) {
        $files[$b.chapters[$i].href] = true;
        if ($b.chapters[$i].content != "") {
            $ids[$b.chapters[$i].href] = idsOf($b.chapters[$i].content);
        }
    }
    for (def i in 0..len($b.resources)) {
        $files[$b.resources[$i].href] = true;
    }
    def t as Targets init Targets{files: $files, ids: $ids};
    def out as list of string;
    for (def i in 0..len($b.chapters)) {
        def from as string init $b.chapters[$i].href;
        if (($b.direction == "ltr" or $b.direction == "rtl") and
            $b.chapters[$i].mediaType == XHTML_TYPE and
            not regex.matches(
            '<html\s[^>]*\bdir\s*=\s*["' + "']" + $b.direction + '["' + "']",
            $b.chapters[$i].content)) {
            $out[] = $from + ": the page is not marked dir=" + shown($b.direction) +
                "; add chapters after setting direction";
        }
        for (def m in regex.findAll(LINK_ATTR, $b.chapters[$i].content)) {
            def link as string init attrText($m);
            if ($link == "" or regex.matches(SCHEME, $link)) {
                continue;
            }
            def w as string init linkWarning($from, $link, $t);
            if ($w != "") {
                $out[] = $w;
            }
        }
    }
    for (def e in $b.toc) {
        if ($e.href == "" or regex.matches(SCHEME, $e.href)) {
            continue;
        }
        # A table of contents href is relative to the package document,
        # where `build` writes nav.xhtml.
        def w as string init linkWarning(NAV_HREF, $e.href, $t);
        if ($w != "") {
            $out[] = "table of contents entry " + shown($e.title) + ": " +
                strings.replace($w, NAV_HREF + ": ", "");
        }
    }
    # Landmarks and page targets are written only into chapters (a link out
    # of the spine is EPUBCheck RSC-011), so one that is not is reported.
    def chapters as map of string to bool init chapterHrefs($b);
    def marks as list of Landmark init $b.landmarks;
    for (def p in $b.pages) {
        $marks[] = Landmark{type: "page", title: $p.label, href: $p.href};
    }
    for (def l in $marks) {
        def what as string init "landmark " + shown($l.type);
        if ($l.type == "page") {
            $what = "page " + shown($l.title);
        }
        def path as string init splitFragment($l.href)[0];
        if (not maps.has($chapters, $path)) {
            $out[] = $what + ": " + shown($l.href) + " is not in a chapter; build leaves it out";
            continue;
        }
        def w as string init linkWarning(NAV_HREF, $l.href, $t);
        if ($w != "") {
            $out[] = $what + ": " + strings.replace($w, NAV_HREF + ": ", "");
        }
    }
    return $out;
}

# A link attribute with what precedes its value (group 1) and the value,
# double (group 2) or single quoted (group 3).
def const LINK_FULL as string init '(\s(?:xlink:)?(?:href|src)\s*=\s*)(?:"([^"]*)"|' + "'([^']*)')";

# The URL of `target` from a file at `from`, both hrefs relative to the
# package document: `../`s up to the directories they share, then down.
func relativeUrl(from as string, target as string) {
    def up as list of string;
    if (dirOf($from) != "") {
        $up = strings.split(dirOf($from), "/");
    }
    def down as list of string init strings.split($target, "/");
    def k as int init 0;
    while ($k < len($up) and $k < len($down) - 1 and $up[$k] == $down[$k]) {
        $k = $k + 1;
    }
    def out as string init strings.repeat("../", len($up) - $k) + strings.join($down[$k..], "/");
    return hrefUrl($out);
}

# A document's links rewritten for a rename: each `href` / `src` that
# leads to `oldHref` now leads to `newHref`, and when the document itself moved
# (from `oldBase` to `newBase`) every link into the book is made relative to
# its new place. Other links keep their text exactly.
func relinked(
    content as string,
    oldBase as string,
    newBase as string,
    oldHref as string,
    newHref as string) {
    def pieces as list of string init regex.split(LINK_FULL, $content);
    def found as list of regex.Match init regex.findAll(LINK_FULL, $content);
    if (len($found) == 0) {
        return $content;
    }
    def out as list of string;
    for (def i in 0..len($found)) {
        $out[] = $pieces[$i];
        def m as regex.Match init $found[$i];
        def raw as string init $m.groups[1];
        if ($raw == "" and $m.groups[2] != "") {
            $raw = $m.groups[2];
        }
        def link as string init pieceText($raw);
        if ($link == "" or strings.startsWith($link, "#") or regex.matches(SCHEME, $link)) {
            $out[] = $m.text;
            continue;
        }
        def target as string init "";
        try {
            $target = resolveIn($oldBase, $link);
        } catch (e) {
            if ($e.kind != ERROR_KIND) {
                throw $e;
            }
            $out[] = $m.text;
            continue;
        }
        def parts as list of string init splitFragment($target);
        def path as string init $parts[0];
        if ($path == $oldHref) {
            $path = $newHref;
        }
        if ($path == $parts[0] and $newBase == $oldBase) {
            $out[] = $m.text;
            continue;
        }
        def url as string init relativeUrl($newBase, $path) + $parts[1];
        $url = strings.replace(
            strings.replace(strings.replace($url, "&", "&amp;"), "<", "&lt;"),
            '"',
            "&quot;");
        $out[] = $m.groups[0] + '"' + $url + '"';
    }
    $out[] = $pieces[len($pieces) - 1];
    return strings.join($out, "");
}

# An href after a rename: its path moved from `oldHref` to `newHref`, its fragment
# kept.
func renamedHref(href as string, oldHref as string, newHref as string) {
    def parts as list of string init splitFragment($href);
    if ($parts[0] != $oldHref) {
        return $href;
    }
    return $newHref + $parts[1];
}

/**
 * Rename a chapter or a file of the book, and every reference to it the
 * deck can see: the links (`href`, `src`, `xlink:href`) in every chapter,
 * the table of contents, the landmarks, the page list and the cover. A
 * chapter that moves to another directory has its own links rewritten to
 * stay pointing where they did. References elsewhere (a stylesheet's
 * `url(...)`, a script) are not rewritten; `check` reports what a rename
 * left unresolved in the chapters. This is how a read book whose names have
 * spaces is made one `build` takes.
 *
 * @param b {Book} the book
 * @param oldHref {string} the current href of the chapter or file
 * @param newHref {string} the new href, as `chapter` and `file` take one
 * @return {Book} the book with the file renamed
 * @throws {EpubError} reason "missing" when no chapter or file has `oldHref`;
 *   "input" for a bad `newHref` or one another file uses
 * @example
 *   for (def c in $b.chapters) {
 *       if (strings.contains($c.href, " ")) {
 *           $b = epub.rename($b, $c.href, strings.replace($c.href, " ", "_"));
 *       }
 *   }
 */
export func rename(b as Book, oldHref as string, newHref as string) {
    if ($oldHref == $newHref) {
        return $b;
    }
    checkHref($newHref, "new");
    def found as bool init resourceAt($b, $oldHref) >= 0;
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].href == $oldHref) {
            $found = true;
        }
    }
    if (not $found) {
        fail("missing", "the book has no chapter or file " + shown($oldHref));
    }
    def low as string init strings.lower($newHref);
    if ($low == NAV_HREF or $low == NCX_HREF or $low == OPF_HREF) {
        fail("input", "href " + shown($newHref) + " is the deck's own");
    }
    for (def i in 0..len($b.chapters)) {
        if ($b.chapters[$i].href != $oldHref and strings.lower($b.chapters[$i].href) == $low) {
            fail("input", "href " + shown($newHref) + " is already used in this book");
        }
    }
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href != $oldHref and strings.lower($b.resources[$i].href) == $low) {
            fail("input", "href " + shown($newHref) + " is already used in this book");
        }
    }
    for (def i in 0..len($b.chapters)) {
        def old as string init $b.chapters[$i].href;
        def now as string init $old;
        if ($old == $oldHref) {
            $now = $newHref;
            $b.chapters[$i].href = $newHref;
        }
        if ($b.chapters[$i].content != "") {
            $b.chapters[$i].content = relinked(
                $b.chapters[$i].content,
                $old,
                $now,
                $oldHref,
                $newHref);
        }
    }
    for (def i in 0..len($b.resources)) {
        if ($b.resources[$i].href == $oldHref) {
            $b.resources[$i].href = $newHref;
        }
    }
    if ($b.cover == $oldHref) {
        $b.cover = $newHref;
    }
    for (def i in 0..len($b.toc)) {
        $b.toc[$i].href = renamedHref($b.toc[$i].href, $oldHref, $newHref);
    }
    for (def i in 0..len($b.landmarks)) {
        $b.landmarks[$i].href = renamedHref($b.landmarks[$i].href, $oldHref, $newHref);
    }
    for (def i in 0..len($b.pages)) {
        $b.pages[$i].href = renamedHref($b.pages[$i].href, $oldHref, $newHref);
    }
    return $b;
}
