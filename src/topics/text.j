# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# epub - a chapter as plain text, and the HTML reading of content documents.
#
# Text is not read from an `xml` tree: `xml.children` hands back element
# children only, so the prose between two elements ("before <a>link</a>
# after") is out of its reach. A well-formed chapter is tokenized instead (its
# tags are balanced, so the markup alone says where text sits); one the `xml`
# parser rejects is read with the bundled `html` parser, whose `Node` keeps
# text and elements in document order. HTML entities (`&nbsp;`, `&mdash;`,
# numeric references) are decoded here, since `html` decodes only the XML five.

# A named or numeric character reference. Up to 8 decimal or 6 hex digits, so
# the number always fits.
def const ENTITY as string init '&([A-Za-z][A-Za-z0-9]{0,31}|#[0-9]{1,8}|#[xX][0-9A-Fa-f]{1,6});';

# HTML 4's Latin-1 entities, U+00A0 to U+00FF in order.
def const LATIN1 as list of string init [
    "nbsp",
    "iexcl",
    "cent",
    "pound",
    "curren",
    "yen",
    "brvbar",
    "sect",
    "uml",
    "copy",
    "ordf",
    "laquo",
    "not",
    "shy",
    "reg",
    "macr",
    "deg",
    "plusmn",
    "sup2",
    "sup3",
    "acute",
    "micro",
    "para",
    "middot",
    "cedil",
    "sup1",
    "ordm",
    "raquo",
    "frac14",
    "frac12",
    "frac34",
    "iquest",
    "Agrave",
    "Aacute",
    "Acirc",
    "Atilde",
    "Auml",
    "Aring",
    "AElig",
    "Ccedil",
    "Egrave",
    "Eacute",
    "Ecirc",
    "Euml",
    "Igrave",
    "Iacute",
    "Icirc",
    "Iuml",
    "ETH",
    "Ntilde",
    "Ograve",
    "Oacute",
    "Ocirc",
    "Otilde",
    "Ouml",
    "times",
    "Oslash",
    "Ugrave",
    "Uacute",
    "Ucirc",
    "Uuml",
    "Yacute",
    "THORN",
    "szlig",
    "agrave",
    "aacute",
    "acirc",
    "atilde",
    "auml",
    "aring",
    "aelig",
    "ccedil",
    "egrave",
    "eacute",
    "ecirc",
    "euml",
    "igrave",
    "iacute",
    "icirc",
    "iuml",
    "eth",
    "ntilde",
    "ograve",
    "oacute",
    "ocirc",
    "otilde",
    "ouml",
    "divide",
    "oslash",
    "ugrave",
    "uacute",
    "ucirc",
    "uuml",
    "yacute",
    "thorn",
    "yuml"
];

# HTML 4's other entities that books use: typography, Latin Extended, Greek,
# arrows and mathematical signs.
def const NAMED as map of string to int init {
    "quot": 34,
    "apos": 39,
    "OElig": 338,
    "oelig": 339,
    "Scaron": 352,
    "scaron": 353,
    "Yuml": 376,
    "fnof": 402,
    "circ": 710,
    "tilde": 732,
    "ensp": 8194,
    "emsp": 8195,
    "thinsp": 8201,
    "zwnj": 8204,
    "zwj": 8205,
    "lrm": 8206,
    "rlm": 8207,
    "ndash": 8211,
    "mdash": 8212,
    "lsquo": 8216,
    "rsquo": 8217,
    "sbquo": 8218,
    "ldquo": 8220,
    "rdquo": 8221,
    "bdquo": 8222,
    "dagger": 8224,
    "Dagger": 8225,
    "bull": 8226,
    "hellip": 8230,
    "permil": 8240,
    "prime": 8242,
    "Prime": 8243,
    "lsaquo": 8249,
    "rsaquo": 8250,
    "oline": 8254,
    "frasl": 8260,
    "euro": 8364,
    "trade": 8482,
    "larr": 8592,
    "uarr": 8593,
    "rarr": 8594,
    "darr": 8595,
    "harr": 8596,
    "minus": 8722,
    "infin": 8734,
    "ne": 8800,
    "le": 8804,
    "ge": 8805,
    "Alpha": 913,
    "Beta": 914,
    "Gamma": 915,
    "Delta": 916,
    "Epsilon": 917,
    "Zeta": 918,
    "Eta": 919,
    "Theta": 920,
    "Iota": 921,
    "Kappa": 922,
    "Lambda": 923,
    "Mu": 924,
    "Nu": 925,
    "Xi": 926,
    "Omicron": 927,
    "Pi": 928,
    "Rho": 929,
    "Sigma": 931,
    "Tau": 932,
    "Upsilon": 933,
    "Phi": 934,
    "Chi": 935,
    "Psi": 936,
    "Omega": 937,
    "alpha": 945,
    "beta": 946,
    "gamma": 947,
    "delta": 948,
    "epsilon": 949,
    "zeta": 950,
    "eta": 951,
    "theta": 952,
    "iota": 953,
    "kappa": 954,
    "lambda": 955,
    "mu": 956,
    "nu": 957,
    "xi": 958,
    "omicron": 959,
    "pi": 960,
    "rho": 961,
    "sigmaf": 962,
    "sigma": 963,
    "tau": 964,
    "upsilon": 965,
    "phi": 966,
    "chi": 967,
    "psi": 968,
    "omega": 969
};

# Elements whose content is not text a reader sees.
def const SKIPPED as list of string init [
    "head",
    "script",
    "style",
    "title",
    "template",
    "noscript"
];

# Elements that start and end a paragraph of the text.
def const BLOCKS as list of string init [
    "address",
    "article",
    "aside",
    "blockquote",
    "body",
    "caption",
    "dd",
    "details",
    "dialog",
    "div",
    "dl",
    "dt",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "hgroup",
    "hr",
    "li",
    "main",
    "nav",
    "ol",
    "p",
    "pre",
    "section",
    "summary",
    "table",
    "tbody",
    "thead",
    "tfoot",
    "tr",
    "ul",
    "html"
];

# A line break inside a paragraph, kept apart from the whitespace that is
# collapsed: a private-use character no text holds.
def const BREAK as string init "\uE000";

# The text gathered so far: the finished paragraphs, the pieces of the open
# one, whether that one is preformatted, how deep in `<pre>` the walk is, and
# how deep in an element whose content is skipped.
def struct TextState {
    paras as list of string,
    line as list of string,
    verbatim as bool,
    pre as int,
    skip as int
};

# The replacement for one character reference. The three that are markup to
# the `html` parser stay references (it decodes them itself); an unknown name
# is kept as written by escaping its `&`.
func entityFor(name as string) {
    if ($name == "amp" or $name == "lt" or $name == "gt") {
        return "&" + $name + ";";
    }
    if (strings.startsWith($name, "#")) {
        def code as int init 0;
        if (strings.startsWith($name, "#x") or strings.startsWith($name, "#X")) {
            $code = convert.toInt($name[2..], 16);
        } else {
            $code = convert.toInt($name[1..]);
        }
        if ($code == 38) {
            return "&amp;";
        }
        if ($code == 60) {
            return "&lt;";
        }
        if ($code == 62) {
            return "&gt;";
        }
        if ($code == 0 or ($code >= 0xD800 and $code <= 0xDFFF) or $code > 0x10FFFF) {
            return "\uFFFD";
        }
        return convert.fromCodepoint($code);
    }
    def at as int init lists.indexOf(LATIN1, $name);
    if ($at >= 0) {
        return convert.fromCodepoint(160 + $at);
    }
    if (maps.has(NAMED, $name)) {
        return convert.fromCodepoint(NAMED[$name]);
    }
    return "&amp;" + $name + ";";
}

# Decode the HTML character references in a document, all but the markup ones,
# in one left-to-right pass (so `&amp;nbsp;` stays the text `&nbsp;`).
func decodeEntities(source as string) {
    if (not strings.contains($source, "&")) {
        return $source;
    }
    def pieces as list of string init regex.split(ENTITY, $source);
    def found as list of regex.Match init regex.findAll(ENTITY, $source);
    def out as list of string;
    for (def i in 0..len($found)) {
        $out[] = $pieces[$i];
        $out[] = entityFor($found[$i].groups[0]);
    }
    $out[] = $pieces[len($pieces) - 1];
    return strings.join($out, "");
}

# A content document as an `html` tree: processing instructions (the XML
# declaration) dropped, CDATA sections made text, entities decoded.
func parseHtml(source as string) {
    def src as string init regex.replace('(?s)<\?.*?\?>', $source, "");
    if (strings.contains($src, "<![CDATA[")) {
        $src = cdataAsText($src);
    }
    return html.parse(decodeEntities($src));
}

# Every CDATA section as the escaped text it stands for.
def const CDATA as string init '(?s)<!\[CDATA\[(.*?)\]\]>';

func cdataAsText(source as string) {
    def pieces as list of string init regex.split(CDATA, $source);
    def found as list of regex.Match init regex.findAll(CDATA, $source);
    def out as list of string;
    for (def i in 0..len($found)) {
        $out[] = $pieces[$i];
        def raw as string init strings.replace($found[$i].groups[0], "&", "&amp;");
        $out[] = strings.replace(strings.replace($raw, "<", "&lt;"), ">", "&gt;");
    }
    $out[] = $pieces[len($pieces) - 1];
    return strings.join($out, "");
}

# How deep the walks over an `html` tree recurse before they go on with an
# explicit stack. Recursion borrows each subtree; the stack has to copy the
# nodes it holds, so it is kept for what lies deeper than a page usually
# nests. The tiny build allows 120 nested calls, blocks and expressions,
# a few per level, so the recursion stays well under it.
def const RECURSION_DEPTH as int init 8;

# Every element with this tag under a node, in document order.
func findTags(n as html.Node, tag as string, acc as list of html.Node) {
    return findTagsAt($n, $tag, $acc, 0);
}

func findTagsAt(n as html.Node, tag as string, acc as list of html.Node, depth as int) {
    for (def c in $n.children) {
        if ($c.kind != html.NodeKind.Element) {
            continue;
        }
        if ($c.tag == $tag) {
            $acc[] = $c;
        }
        if ($depth + 1 < RECURSION_DEPTH) {
            $acc = findTagsAt($c, $tag, $acc, $depth + 1);
        } else {
            $acc = findTagsDeep($c, $tag, $acc);
        }
    }
    return $acc;
}

# `findTags` past RECURSION_DEPTH: the same walk with an explicit stack.
func findTagsDeep(n as html.Node, tag as string, acc as list of html.Node) {
    def stack as list of html.Node;
    def top as int init -1;
    def k as int init len($n.children) - 1;
    while ($k >= 0) {
        if ($n.children[$k].kind == html.NodeKind.Element) {
            $top = $top + 1;
            if ($top < len($stack)) {
                $stack[$top] = $n.children[$k];
            } else {
                $stack[] = $n.children[$k];
            }
        }
        $k = $k - 1;
    }
    while ($top >= 0) {
        def c as html.Node init $stack[$top];
        $top = $top - 1;
        if ($c.tag == $tag) {
            $acc[] = $c;
        }
        $k = len($c.children) - 1;
        while ($k >= 0) {
            if ($c.children[$k].kind == html.NodeKind.Element) {
                $top = $top + 1;
                if ($top < len($stack)) {
                    $stack[$top] = $c.children[$k];
                } else {
                    $stack[] = $c.children[$k];
                }
            }
            $k = $k - 1;
        }
    }
    return $acc;
}

# An attribute of an element, "" when it has none: `html.attrOf` without the
# call into the module, which rebuilds the node, subtree and all.
func attrValue(n as html.Node, name as string) {
    for (def i in 0..len($n.attrs)) {
        if ($n.attrs[$i].name == $name) {
            return $n.attrs[$i].value;
        }
    }
    return "";
}

func gatherText(n as html.Node, acc as list of string) {
    return gatherTextAt($n, $acc, 0);
}

func gatherTextAt(n as html.Node, acc as list of string, depth as int) {
    for (def c in $n.children) {
        if ($c.kind == html.NodeKind.Text) {
            $acc[] = $c.text;
        } elseif ($c.kind == html.NodeKind.Element) {
            if ($depth + 1 < RECURSION_DEPTH) {
                $acc = gatherTextAt($c, $acc, $depth + 1);
            } else {
                $acc = gatherTextDeep($c, $acc);
            }
        }
    }
    return $acc;
}

func collapse(s as string) {
    return strings.trim(regex.replace('[ \t\n\r\f]+', $s, " "));
}

func gatherTextDeep(n as html.Node, acc as list of string) {
    def stack as list of html.Node init [$n];
    def top as int init 0;
    def first as bool init true;
    while ($top >= 0) {
        def c as html.Node init $stack[$top];
        $top = $top - 1;
        if ($c.kind == html.NodeKind.Text and not $first) {
            $acc[] = $c.text;
            continue;
        }
        $first = false;
        if ($c.kind != html.NodeKind.Element) {
            continue;
        }
        def k as int init len($c.children) - 1;
        while ($k >= 0) {
            $top = $top + 1;
            if ($top < len($stack)) {
                $stack[$top] = $c.children[$k];
            } else {
                $stack[] = $c.children[$k];
            }
            $k = $k - 1;
        }
    }
    return $acc;
}

# The text of an element on one line, whitespace collapsed: a heading, a link.
func inlineText(n as html.Node) {
    return collapse(strings.join(gatherText($n, []), " "));
}

# End the open paragraph. Ordinary text has its whitespace collapsed and
# keeps its line breaks; preformatted text is kept as written.
func flush(st as TextState) {
    def joined as string init strings.join($st.line, "");
    def para as string init "";
    if ($st.verbatim) {
        $para = strings.trimRight(regex.replace('^\n', $joined, ""));
        $para = strings.replace($para, BREAK, "\n");
    } else {
        $para = collapse($joined);
        $para = regex.replace(' ?' + BREAK + ' ?', $para, "\n");
        $para = strings.trim($para);
    }
    if ($para != "") {
        $st.paras[] = $para;
    }
    $st.line = [];
    $st.verbatim = false;
    return $st;
}

# The walk is a stream of three events, fed by the `html` tree for a chapter
# that is not well formed and by a tokenizer for one that is, so the two give
# the same text.

func onText(st as TextState, s as string) {
    if ($st.skip > 0) {
        return $st;
    }
    $st.line[] = $s;
    if ($st.pre > 0) {
        $st.verbatim = true;
    }
    return $st;
}

func onOpen(st as TextState, tag as string) {
    if (lists.contains(SKIPPED, $tag)) {
        $st.skip = $st.skip + 1;
        return $st;
    }
    if ($st.skip > 0) {
        return $st;
    }
    if ($tag == "br") {
        $st.line[] = BREAK;
    } elseif ($tag == "td" or $tag == "th") {
        $st.line[] = " ";
    } elseif (lists.contains(BLOCKS, $tag)) {
        $st = flush($st);
        if ($tag == "pre") {
            $st.pre = $st.pre + 1;
        }
    }
    return $st;
}

func onClose(st as TextState, tag as string) {
    if (lists.contains(SKIPPED, $tag)) {
        $st.skip = $st.skip - 1;
        return $st;
    }
    if ($st.skip > 0) {
        return $st;
    }
    if (lists.contains(BLOCKS, $tag)) {
        if ($tag == "pre") {
            $st.pre = $st.pre - 1;
        }
        $st = flush($st);
    }
    return $st;
}

# The `html` tree as events: recursion to RECURSION_DEPTH, then `walkDeep`.
func walk(n as html.Node, st as TextState) {
    return walkAt($n, $st, 0);
}

func walkAt(n as html.Node, st as TextState, depth as int) {
    for (def c in $n.children) {
        if ($c.kind == html.NodeKind.Text) {
            $st = onText($st, $c.text);
        } elseif ($c.kind == html.NodeKind.Element) {
            $st = onOpen($st, $c.tag);
            if ($depth + 1 < RECURSION_DEPTH) {
                $st = walkAt($c, $st, $depth + 1);
            } else {
                $st = walkDeep($c, $st);
            }
            $st = onClose($st, $c.tag);
        }
    }
    return $st;
}

# `walk` past RECURSION_DEPTH, depth first with an explicit stack (the node
# and the next child to visit, per level).
func walkDeep(n as html.Node, st as TextState) {
    def nodes as list of html.Node init [$n];
    def next as list of int init [0];
    def top as int init 0;
    while ($top >= 0) {
        def i as int init $next[$top];
        if ($i >= len($nodes[$top].children)) {
            if ($top > 0) {
                $st = onClose($st, $nodes[$top].tag);
            }
            $top = $top - 1;
            continue;
        }
        $next[$top] = $i + 1;
        def c as html.Node init $nodes[$top].children[$i];
        if ($c.kind == html.NodeKind.Text) {
            $st = onText($st, $c.text);
        } elseif ($c.kind == html.NodeKind.Element) {
            $st = onOpen($st, $c.tag);
            $top = $top + 1;
            if ($top < len($nodes)) {
                $nodes[$top] = $c;
                $next[$top] = 0;
            } else {
                $nodes[] = $c;
                $next[] = 0;
            }
        }
    }
    return $st;
}

# Markup of a well-formed document, one token at a time: a comment, a CDATA
# section (group 1), a processing instruction, a declaration, or a tag (end
# slash, local name without its prefix, empty-element slash). Attribute values are quoted, so a `>`
# in one does not end its tag.
def const TOKEN as string init '(?s)<!--.*?-->|<!\[CDATA\[(.*?)\]\]>|<\?.*?\?>|<![A-Za-z](?:[^>\[]|\[[^\]]*\])*>|<(/?)(?:[A-Za-z_][A-Za-z0-9_.-]*:)?([A-Za-z_][A-Za-z0-9_.-]*)(?:[^>"' +
    "'" + ']|"[^"]*"|' + "'[^']*'" + ')*?(/?)>';

# The tags `onOpen` and `onClose` act on; for any other tag (an inline `<span>`,
# `<em>`, MathML's `<mi>`) both are no-ops, so `tokenWalk` skips the calls.
def const ACTIVE as map of string to bool init {
    "br": true,
    "td": true,
    "th": true,
    "head": true,
    "script": true,
    "style": true,
    "title": true,
    "template": true,
    "noscript": true,
    "address": true,
    "article": true,
    "aside": true,
    "blockquote": true,
    "body": true,
    "caption": true,
    "dd": true,
    "details": true,
    "dialog": true,
    "div": true,
    "dl": true,
    "dt": true,
    "fieldset": true,
    "figcaption": true,
    "figure": true,
    "footer": true,
    "form": true,
    "h1": true,
    "h2": true,
    "h3": true,
    "h4": true,
    "h5": true,
    "h6": true,
    "header": true,
    "hgroup": true,
    "hr": true,
    "li": true,
    "main": true,
    "nav": true,
    "ol": true,
    "p": true,
    "pre": true,
    "section": true,
    "summary": true,
    "table": true,
    "tbody": true,
    "thead": true,
    "tfoot": true,
    "tr": true,
    "ul": true,
    "html": true
};

# A text piece of a well-formed document: its references decoded (the HTML
# ones, then the XML five), and nothing done for a piece without any.
func pieceText(piece as string) {
    if (not strings.contains($piece, "&")) {
        return $piece;
    }
    return html.unescape(decodeEntities($piece));
}

# A well-formed document as events, without building a tree: the tokens are
# found natively and only the markup is looked at, which is several times
# faster than the `html` parser on a large chapter. Only the `<body>` counts
# when there is one. Text goes to `onText` and the tags in ACTIVE to `onOpen`
# / `onClose`; the per-token work is kept small, since a MathML chapter has
# hundreds of thousands of tokens.
func tokenWalk(source as string, st as TextState) {
    def pieces as list of string init regex.split(TOKEN, $source);
    def found as list of regex.Match init regex.findAll(TOKEN, $source);
    def hasBody as bool init regex.matches('<([A-Za-z_][A-Za-z0-9_.-]*:)?body[\s/>]', $source);
    def inBody as bool init not $hasBody;
    for (def i in 0..len($found)) {
        # `onText`, inlined: it runs once per piece of text.
        if ($inBody and $st.skip == 0 and $pieces[$i] != "") {
            $st.line[] = pieceText($pieces[$i]);
            if ($st.pre > 0) {
                $st.verbatim = true;
            }
        }
        def tag as string init $found[$i].groups[2];
        if ($tag == "") {
            if ($inBody and strings.startsWith($found[$i].text, "<![CDATA[")) {
                $st = onText($st, $found[$i].groups[0]);
            }
            continue;
        }
        if (not maps.has(ACTIVE, $tag)) {
            $tag = strings.lower($tag);
            if (not maps.has(ACTIVE, $tag)) {
                continue;
            }
        }
        def closing as bool init $found[$i].groups[1] == "/";
        def empty as bool init $found[$i].groups[3] == "/";
        if ($tag == "body" and $hasBody) {
            $inBody = not $closing and not $empty;
            if (not $inBody) {
                $st = onClose($st, $tag);
            } else {
                $st = onOpen($st, $tag);
            }
            continue;
        }
        if (not $inBody) {
            continue;
        }
        if ($closing) {
            $st = onClose($st, $tag);
        } else {
            $st = onOpen($st, $tag);
            if ($empty) {
                $st = onClose($st, $tag);
            }
        }
    }
    if ($inBody and len($pieces) > len($found) and $pieces[len($pieces) - 1] != "") {
        $st = onText($st, pieceText($pieces[len($pieces) - 1]));
    }
    return $st;
}

/**
 * A chapter as plain text: the text of its `<body>` in reading order, one
 * paragraph per block (`<p>`, a heading, a list item, ...) with a blank line
 * between them. Whitespace is collapsed as a browser would, `<br/>` is a line
 * break, `<pre>` is kept as written, and scripts, styles and the `<head>` are
 * left out. HTML entities are decoded (`&nbsp;` is U+00A0). A chapter that is
 * not well-formed XML (`wellFormed` false) is read with the `html` parser.
 *
 * @param c {Chapter} the chapter
 * @return {string} its text
 * @throws {Error} kind "limit" for a document past the `html` parser's
 *   nesting or node budget
 * @example
 *   for (def c in $b.chapters) {
 *       io.printf("%s\n\n", epub.text($c));
 *   }
 */
export func text(c as Chapter) {
    def st as TextState init TextState{paras: [], line: [], verbatim: false, pre: 0, skip: 0};
    if ($c.wellFormed) {
        $st = tokenWalk($c.content, $st);
        return strings.join(flush($st).paras, "\n\n");
    }
    return htmlText($c.content);
}

# The text of a document read as HTML: the fallback for a chapter that is not
# well-formed XML.
func htmlText(source as string) {
    def st as TextState init TextState{paras: [], line: [], verbatim: false, pre: 0, skip: 0};
    def doc as html.Node init parseHtml($source);
    def bodies as list of html.Node init findTags($doc, "body", []);
    if (len($bodies) > 0) {
        $st = onOpen($st, "body");
        $st = walk($bodies[0], $st);
        $st = onClose($st, "body");
    } else {
        $st = walk($doc, $st);
    }
    return strings.join(flush($st).paras, "\n\n");
}
