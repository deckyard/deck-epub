# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# epub - reading a book: `read`, `readWith`, `resource`, `resolve`.
#
# Strict where the format is the container's: the `mimetype` entry, the
# container document and the package document must be what the specification
# says, or the book is refused. Lenient where real-world books are not:
# a chapter that is not well-formed XML is still read, as HTML.

def const IDPF_OBFUSCATION as string init "http://www.idpf.org/2008/embedding";
def const ADOBE_OBFUSCATION as string init "http://ns.adobe.com/pdf/enc#RC";

# Files whose presence alone means the book is locked: Adobe ADEPT, Readium
# LCP, Apple FairPlay.
def const DRM_FILES as map of string to string init {
    "META-INF/rights.xml": "Adobe ADEPT",
    "META-INF/license.lcpl": "Readium LCP",
    "META-INF/sinf.xml": "Apple FairPlay"
};

# A URL with a scheme points outside the book (a remote resource).
def const SCHEME as string init '^[A-Za-z][A-Za-z0-9+.-]*:';

# The unpacked archive: its entries, where each name is, and each name by
# its lower case (for a manifest href that differs from it only in case),
# with the lower-case names more than one entry shares.
def struct Archive {
    entries as list of archive.Entry,
    index as map of string to int,
    folded as map of string to string,
    ambiguous as map of string to bool
};

# One manifest item, as the package document lists it.
def struct Item {
    id as string,
    href as string,
    path as string,
    mediaType as string,
    properties as string,
    fallback as string,
    mediaOverlay as string
};

/**
 * The default caps of `readWith`, to adjust:
 * `$o = epub.readOptions(); $o.maxBytes = 1048576;`.
 *
 * @return {ReadOptions} `DEFAULT_MAX_BYTES`, `DEFAULT_MAX_ENTRIES`,
 *   `DEFAULT_MAX_ENTRY_BYTES` and `DEFAULT_MAX_TOTAL_BYTES`
 */
export func readOptions() {
    return ReadOptions{
        maxBytes: DEFAULT_MAX_BYTES,
        maxEntries: DEFAULT_MAX_ENTRIES,
        maxEntryBytes: DEFAULT_MAX_ENTRY_BYTES,
        maxTotalBytes: DEFAULT_MAX_TOTAL_BYTES
    };
}

# The largest int: a cap that is no cap (`math.MAX_INT` from Jennifer
# 0.28.0 on, whose `archive` refuses a negative one; written out so 0.27.0
# runs it too).
def const NO_LIMIT as int init 9223372036854775807;

# A cap as configured: 0 is the default, a negative value is no cap
# (`NO_LIMIT`).
func capOf(value as int, fallback as int) {
    if ($value == 0) {
        return $fallback;
    }
    if ($value < 0) {
        return NO_LIMIT;
    }
    return $value;
}

# --- the archive ---------------------------------------------------------

# Whether the bytes start as a zip archive does: a local file header.
func checkZip(data as bytes) {
    if (len($data) < 30 or not binary.startsWith($data, le32(0x04034b50))) {
        fail("archive", "not a zip archive");
    }
}

# The OCF rule for `mimetype`: the first entry, stored, holding exactly
# `application/epub+zip`. What the raw first local header says decides
# whether it holds; an unpacked entry no longer says how it was stored. A
# book that breaks it in form only (`mimetype` deflated, not first, or with
# trailing whitespace) is read, and the note returned says how; one without
# a `mimetype`, or with other content, is refused. "" for a perfect one.
func mimetypeNote(data as bytes, a as Archive, methods as map of string to int) {
    if (not hasEntry($a, "mimetype")) {
        fail("container", "the archive has no mimetype entry");
    }
    def content as bytes init entryData($a, "mimetype");
    if ($content != bytesOf(MIMETYPE) and
        strings.trim(encoding.decode("utf-8", $content)) != MIMETYPE) {
        fail("container", "the mimetype entry does not say " + MIMETYPE);
    }
    def wrong as list of string;
    def nameLen as int init binary.readUint("le", $data, 26, 2);
    if (len($data) < 30 + $nameLen or $data[30..30 + $nameLen] != bytesOf("mimetype")) {
        $wrong[] = "not the first entry";
    }
    if (maps.has($methods, "mimetype") and $methods["mimetype"] != 0) {
        $wrong[] = "compressed";
    }
    if ($content != bytesOf(MIMETYPE)) {
        $wrong[] = "followed by whitespace";
    }
    if (len($wrong) == 0) {
        return "";
    }
    return "the mimetype entry is " + strings.join($wrong, ", ") + "; read anyway";
}

# The compression method of every entry, read from the central directory,
# since an unpacked entry no longer says how it was stored. `unpack` has
# already accepted the archive; a directory this cannot walk (zip64, a
# comment that hides the end record) gives what it found so far.
func entryMethods(data as bytes) {
    def out as map of string to int;
    def sig as bytes init le32(0x06054b50);
    def from as int init len($data) - 65557;
    if ($from < 0) {
        $from = 0;
    }
    def eocd as int init -1;
    def at as int init binary.indexOf($data, $sig, $from);
    while ($at >= 0) {
        $eocd = $at;
        $at = binary.indexOf($data, $sig, $at + 1);
    }
    if ($eocd < 0 or $eocd + 22 > len($data)) {
        return $out;
    }
    def count as int init binary.readUint("le", $data, $eocd + 10, 2);
    def p as int init binary.readUint("le", $data, $eocd + 16, 4);
    def central as bytes init le32(0x02014b50);
    for (def i in 0..$count) {
        if ($p + 46 > len($data) or $data[$p..$p + 4] != $central) {
            return $out;
        }
        def nameLen as int init binary.readUint("le", $data, $p + 28, 2);
        if ($p + 46 + $nameLen > len($data)) {
            return $out;
        }
        def name as string init encoding.decode("utf-8", $data[$p + 46..$p + 46 + $nameLen]);
        $out[$name] = binary.readUint("le", $data, $p + 10, 2);
        $p = $p + 46 + $nameLen + binary.readUint("le", $data, $p + 30, 2) +
            binary.readUint("le", $data, $p + 32, 2);
    }
    return $out;
}

# Whether an entry other than `mimetype` is deflated (method not 0).
func deflatedEntries(methods as map of string to int) {
    for (def name in $methods) {
        if ($name != "mimetype" and $methods[$name] != 0) {
            return true;
        }
    }
    return false;
}

# The archive's entries, with its failures as reason "archive" (a cap passes
# on as "limit"). The result is returned from inside the `try`: assigned to a
# variable there, the whole list would be copied.
func unpackEntries(data as bytes, opts as ReadOptions) {
    try {
        return archive.unpackWith(
            "zip",
            $data,
            archive.UnpackOptions{
                maxTotalBytes: capOf($opts.maxTotalBytes, DEFAULT_MAX_TOTAL_BYTES),
                maxEntryBytes: capOf($opts.maxEntryBytes, DEFAULT_MAX_ENTRY_BYTES),
                maxEntries: capOf($opts.maxEntries, DEFAULT_MAX_ENTRIES),
                skipSpecial: false
            });
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail("archive", "cannot unpack: " + $e.message);
    }
    return [];
}

func unpack(data as bytes, opts as ReadOptions) {
    def found as list of archive.Entry init unpackEntries($data, $opts);
    def index as map of string to int;
    def folded as map of string to string;
    def ambiguous as map of string to bool;
    for (def i in 0..len($found)) {
        def name as string init $found[$i].name;
        if (maps.has($index, $name)) {
            fail("archive", "the archive holds " + shown($name) + " twice");
        }
        $index[$name] = $i;
        def low as string init strings.lower($name);
        if (maps.has($folded, $low)) {
            $ambiguous[$low] = true;
        }
        $folded[$low] = $name;
    }
    return Archive{entries: $found, index: $index, folded: $folded, ambiguous: $ambiguous};
}

func hasEntry(a as Archive, name as string) {
    return maps.has($a.index, $name);
}

func entryData(a as Archive, name as string) {
    return $a.entries[$a.index[$name]].data;
}

# An entry as text: UTF-8, or UTF-16 announced by its byte order mark (both
# are the encodings XML and EPUB allow), with the byte order mark dropped.
func entryText(a as Archive, name as string, reason as string) {
    def data as bytes init entryData($a, $name);
    if (len($data) >= 2 and
        ($data[0] == 0xFF and $data[1] == 0xFE or $data[0] == 0xFE and $data[1] == 0xFF)) {
        return utf16Text($data, $name, $reason);
    }
    def out as string;
    try {
        $out = encoding.decode("utf-8", $data);
    } catch (e) {
        fail($reason, shown($name) + " is neither UTF-8 nor UTF-16 text");
    }
    if (strings.startsWith($out, "\uFEFF")) {
        $out = $out[1..];
    }
    return $out;
}

# UTF-16 after its byte order mark, which says the byte order. The `convert`
# library decodes UTF-8 only, so the code units are combined here; an odd
# length or an unpaired surrogate is not UTF-16.
func utf16Text(data as bytes, name as string, reason as string) {
    def order as string init "le";
    if ($data[0] == 0xFE) {
        $order = "be";
    }
    if (len($data) % 2 != 0) {
        fail($reason, shown($name) + " is not UTF-16 text");
    }
    def units as list of int init binary.readInts($order, $data, 2, (len($data) - 2) // 2, 2);
    def out as list of string;
    def i as int init 0;
    while ($i < len($units)) {
        def u as int init $units[$i] & 0xFFFF;
        $i = $i + 1;
        if ($u >= 0xD800 and $u <= 0xDBFF and $i < len($units)) {
            def low as int init $units[$i] & 0xFFFF;
            if ($low >= 0xDC00 and $low <= 0xDFFF) {
                $out[] = convert.fromCodepoint(0x10000 + (($u - 0xD800) << 10) + ($low - 0xDC00));
                $i = $i + 1;
                continue;
            }
        }
        if ($u >= 0xD800 and $u <= 0xDFFF) {
            fail($reason, shown($name) + " is not UTF-16 text");
        }
        $out[] = convert.fromCodepoint($u);
    }
    return strings.join($out, "");
}

# A document as text, with the note that says how it was decoded when that
# was a tolerance ("" otherwise).
def struct Decoded {
    text as string,
    note as string
};

# The charset a document declares in its first KiB, lower case, "" for none:
# the XML declaration's `encoding`, and for a content document also an HTML
# `<meta charset>` or `http-equiv` Content-Type. Read as Latin-1, which
# decodes any bytes and keeps ASCII as it is.
func declaredCharset(data as bytes, page as bool) {
    def n as int init len($data);
    if ($n > 1024) {
        $n = 1024;
    }
    def head as string init encoding.decode("iso-8859-1", $data[..$n]);
    def m as regex.Match init regex.find(
        '^\s*<\?xml[^>]*\sencoding\s*=\s*["' + "']([A-Za-z0-9._-]+)",
        $head);
    if ($m.start >= 0) {
        return strings.lower($m.groups[0]);
    }
    if ($page) {
        $m = regex.find('(?i)<meta[^>]*charset\s*=\s*["' + "']?([A-Za-z0-9._-]+)", $head);
        if ($m.start >= 0) {
            return strings.lower($m.groups[0]);
        }
    }
    return "";
}

# The `encoding` codec for a declared legacy charset: an ISO-8859 or Windows
# code page that library decodes, "" for any other name.
func legacyCodec(charset as string) {
    def name as string init strings.replace($charset, "_", "-");
    if (not strings.startsWith($name, "iso-8859-") and not strings.startsWith($name, "windows-")) {
        return "";
    }
    if (not lists.contains(encoding.codecs(), $name)) {
        return "";
    }
    return $name;
}

# A document that may be in a legacy charset: a chapter, the navigation
# document (`page`, where a `<meta>` may declare it), the package document
# or the NCX (the XML declaration only). UTF-8 and UTF-16 come first, so a
# valid UTF-8 document that declares Latin-1 is read as UTF-8 (its bytes
# would turn to mojibake otherwise); bytes that are not UTF-8 are decoded
# with the declared ISO-8859 or Windows code page, and noted. Without such a
# declaration they are refused, as before.
func documentText(a as Archive, name as string, reason as string, page as bool) {
    def data as bytes init entryData($a, $name);
    if (len($data) >= 2 and
        ($data[0] == 0xFF and $data[1] == 0xFE or $data[0] == 0xFE and $data[1] == 0xFF)) {
        return Decoded{text: utf16Text($data, $name, $reason), note: ""};
    }
    def utf8 as bool init true;
    def out as string;
    try {
        $out = encoding.decode("utf-8", $data);
    } catch (e) {
        $utf8 = false;
    }
    if ($utf8) {
        if (strings.startsWith($out, "\uFEFF")) {
            $out = $out[1..];
        }
        def note as string init "";
        if (not encoding.isAscii($data)) {
            def label as string init legacyCodec(declaredCharset($data, $page));
            if ($label != "") {
                $note = shown($name) + " declares " + $label + " but is valid UTF-8; read as UTF-8";
            }
        }
        return Decoded{text: $out, note: $note};
    }
    def charset as string init declaredCharset($data, $page);
    def codec as string init legacyCodec($charset);
    if ($codec == "") {
        def said as string init "";
        if ($charset != "") {
            $said = ", and its charset " + shown($charset) + " is not ISO-8859 or Windows";
        }
        fail($reason, shown($name) + " is neither UTF-8 nor UTF-16 text" + $said);
    }
    return Decoded{
        text: encoding.decode($codec, $data),
        note: shown($name) + " is not UTF-8; read as " + $codec + ", the charset it declares"
    };
}

# Strict XML: a document the container or the package depends on.
func strictXml(a as Archive, name as string, reason as string) {
    if (not hasEntry($a, $name)) {
        fail($reason, shown($name) + " is missing");
    }
    return parsedXml(entryText($a, $name, $reason), $name, $reason);
}

func parsedXml(text as string, name as string, reason as string) {
    try {
        return xml.decode($text);
    } catch (e) {
        if (isGeneric($e.kind)) {
            throw $e;
        }
        fail($reason, shown($name) + " is not well-formed XML: " + $e.message);
    }
    return xml.element("x");
}

# The package document or the NCX: strict XML, but in a legacy charset when
# it declares one; the note says so.
def struct XmlRead {
    root as xml.Value,
    note as string
};

func declaredXml(a as Archive, name as string, reason as string) {
    if (not hasEntry($a, $name)) {
        fail($reason, shown($name) + " is missing");
    }
    def d as Decoded init documentText($a, $name, $reason, false);
    return XmlRead{root: parsedXml($d.text, $name, $reason), note: $d.note};
}

# Percent-decode an href ("a%20b.xhtml" names "a b.xhtml").
func unescapeHref(href as string, reason as string) {
    if (not strings.contains($href, "%")) {
        return $href;
    }
    try {
        return encoding.decode("utf-8", encoding.fromText("uri-percent", $href));
    } catch (e) {
        fail($reason, "href " + shown($href) + " has a bad percent escape");
    }
    return $href;
}

# --- protection ----------------------------------------------------------

# Refuse a DRM-protected book, and list the obfuscated fonts: zip path to the
# algorithm that undoes them.
func protection(a as Archive) {
    for (def name in DRM_FILES) {
        if (hasEntry($a, $name)) {
            fail("drm", "the book is protected with " + DRM_FILES[$name] + " (" + $name + ")");
        }
    }
    def out as map of string to string;
    if (not hasEntry($a, "META-INF/encryption.xml")) {
        return $out;
    }
    def root as xml.Value init strictXml($a, "META-INF/encryption.xml", "container");
    def ns as map of string to string init {"e": ENC_NS};
    for (def data in xml.findAll($root, "*:EncryptedData")) {
        def algorithm as string init "";
        if (xml.has($data, "e:EncryptionMethod", $ns)) {
            def method as xml.Value init xml.get($data, "e:EncryptionMethod", $ns);
            if (xml.hasAttr($method, "Algorithm")) {
                $algorithm = xml.attr($method, "Algorithm");
            }
        }
        def uri as string init "";
        if (xml.has($data, "e:CipherData/e:CipherReference", $ns)) {
            def ref as xml.Value init xml.get($data, "e:CipherData/e:CipherReference", $ns);
            if (xml.hasAttr($ref, "URI")) {
                $uri = cleanPath(unescapeHref(xml.attr($ref, "URI"), "container"));
            }
        }
        if ($algorithm != IDPF_OBFUSCATION and $algorithm != ADOBE_OBFUSCATION) {
            fail("drm", shown($uri) + " is encrypted (" + $algorithm + ")");
        }
        if ($uri != "") {
            $out[$uri] = $algorithm;
        }
    }
    return $out;
}

# Undo font obfuscation: the first 1040 (IDPF) or 1024 (Adobe) bytes are
# XORed with a key derived from the book's identifier.
func deobfuscate(data as bytes, algorithm as string, uid as string, identifiers as list of string) {
    def key as bytes;
    def n as int init 1040;
    if ($algorithm == IDPF_OBFUSCATION) {
        $key = hash.compute("sha1", bytesOf(regex.replace('[ \t\r\n]', $uid, "")));
    } else {
        $n = 1024;
        def hex as string init "";
        for (def id in lists.concat([$uid], $identifiers)) {
            def bare as string init strings.lower(regex.replace(
                '[^0-9A-Fa-f]',
                regex.replace('^urn:uuid:', $id, ""),
                ""));
            if (len($bare) == 32) {
                $hex = $bare;
                break;
            }
        }
        if ($hex == "") {
            fail("package", "an Adobe-obfuscated font needs a UUID identifier");
        }
        $key = encoding.fromText("hex", $hex);
    }
    if (len($data) < $n) {
        $n = len($data);
    }
    return binary.concat(binary.bitXor($data[..$n], $key), $data[$n..len($data)]);
}

# --- the container and the package --------------------------------------

# The package document's path, from META-INF/container.xml.
func rootfileOf(a as Archive) {
    def root as xml.Value init strictXml($a, "META-INF/container.xml", "container");
    if (xml.localName($root) != "container" or xml.namespace($root) != OCF_NS) {
        fail("container", "META-INF/container.xml is not an OCF container");
    }
    for (def r in xml.findAll($root, "c:rootfiles/c:rootfile", {"c": OCF_NS})) {
        if (xml.hasAttr($r, "media-type") and xml.attr($r, "media-type") == OPF_TYPE) {
            if (not xml.hasAttr($r, "full-path")) {
                fail("container", "a rootfile has no full-path");
            }
            def full as string init cleanPath(xml.attr($r, "full-path"));
            if ($full == "" or climbsOut($full)) {
                fail(
                    "container",
                    "rootfile " + shown(xml.attr($r, "full-path")) + " is not inside the book");
            }
            return $full;
        }
    }
    fail("container", "META-INF/container.xml names no package document");
    return "";
}

func firstText(parent as xml.Value, path as string, ns as map of string to string) {
    if (not xml.has($parent, $path, $ns)) {
        return "";
    }
    return strings.trim(xml.text(xml.get($parent, $path, $ns)));
}

func requiredText(
    parent as xml.Value,
    path as string,
    ns as map of string to string,
    what as string) {
    def out as string init firstText($parent, $path, $ns);
    if ($out == "") {
        fail("package", "the package document has no " + $what);
    }
    return $out;
}

func requiredAttr(node as xml.Value, name as string, what as string) {
    if (not xml.hasAttr($node, $name)) {
        fail("package", $what + " has no " + $name);
    }
    return xml.attr($node, $name);
}

# The manifest, in document order. Every local item must be in the archive;
# a remote one (`https://...`) is left out.
# The manifest as read: its items, the ids of those left out because the
# archive lacks their file, and the notes.
def struct Manifest {
    items as list of Item,
    missing as map of string to bool,
    notes as list of string
};

# A path relative to the package directory, for a path from the root.
func relativeTo(dir as string, full as string) {
    if ($dir == "") {
        return $full;
    }
    if (strings.startsWith($full, $dir + "/")) {
        return $full[len($dir) + 1..];
    }
    return strings.replicate("../", strings.count($dir, "/") + 1) + $full;
}

# The manifest, in document order. A remote item (`https://...`) is left
# out. A local one whose file the archive lacks is left out too, with a note
# (a spine item that names it is still an error). A file found only by
# ignoring case is used, with a note, unless several names match. An href
# starting with `/` is relative to the container root, not the package.
func manifestOf(a as Archive, pkg as xml.Value, dir as string, ns as map of string to string) {
    if (not xml.has($pkg, "o:manifest", $ns)) {
        fail("package", "the package document has no manifest");
    }
    def out as Manifest init Manifest{items: [], missing: {}, notes: []};
    def seen as map of string to bool;
    for (def node in xml.findAll($pkg, "o:manifest/o:item", $ns)) {
        def id as string init requiredAttr($node, "id", "a manifest item");
        def href as string init requiredAttr($node, "href", "manifest item " + shown($id));
        def media as string init requiredAttr($node, "media-type", "manifest item " + shown($id));
        if (maps.has($seen, $id)) {
            fail("package", "manifest id " + shown($id) + " is used twice");
        }
        $seen[$id] = true;
        if (regex.matches(SCHEME, $href)) {
            continue;
        }
        def rel as string init cleanPath(unescapeHref(splitFragment($href)[0], "package"));
        def full as string init joinPath($dir, $rel);
        if (strings.startsWith($href, "/")) {
            $full = $rel;
            $rel = relativeTo($dir, $full);
        }
        if ($full == "" or climbsOut($full)) {
            fail("package", "manifest item " + shown($id) + " is outside the book");
        }
        def path as string init $full;
        if (not hasEntry($a, $full)) {
            def low as string init strings.lower($full);
            if (maps.has($a.ambiguous, $low)) {
                fail(
                    "package",
                    "manifest item " + shown($id) + " names " + shown($full) +
                        ", which matches several names in the archive when case is ignored");
            }
            if (not maps.has($a.folded, $low)) {
                $out.missing[$id] = true;
                $out.notes[] = "manifest item " + shown($id) + " names " + shown($full) +
                    ", which is not in the archive; left out";
                continue;
            }
            $path = $a.folded[$low];
            $out.notes[] = "manifest item " + shown($id) + " names " + shown($full) + "; read " +
                shown($path) + ", which differs only in case";
        }
        def props as string init "";
        if (xml.hasAttr($node, "properties")) {
            $props = strings.trim(xml.attr($node, "properties"));
        }
        def fallback as string init "";
        if (xml.hasAttr($node, "fallback")) {
            $fallback = xml.attr($node, "fallback");
        }
        $out.items[] = Item{
            id: $id,
            href: $rel,
            path: $path,
            mediaType: $media,
            properties: $props,
            fallback: $fallback,
            mediaOverlay: attrOr($node, "media-overlay")
        };
    }
    return $out;
}

func itemIndex(items as list of Item, id as string) {
    for (def i in 0..len($items)) {
        if ($items[$i].id == $id) {
            return $i;
        }
    }
    return -1;
}

# Resolve an href written in the document at `base` (both relative to the
# package directory) to a path relative to the package directory, keeping
# its fragment. A URL with a scheme is returned as written.
func resolveIn(base as string, href as string) {
    if (regex.matches(SCHEME, $href)) {
        return $href;
    }
    def parts as list of string init splitFragment($href);
    if ($parts[0] == "") {
        return $base + $parts[1];
    }
    return joinPath(dirOf($base), unescapeHref($parts[0], "toc")) + $parts[1];
}

/**
 * Resolve a link in a book file to the href of its target: `resolve(ch.href,
 * "../img/a.png")` from `text/ch1.xhtml` is `img/a.png`. A fragment is kept;
 * a URL with a scheme comes back as written.
 *
 * @param base {string} the href of the file the link is in
 * @param href {string} the link as written there
 * @return {string} the target, relative to the package document
 * @throws {EpubError} reason "toc" for a bad percent escape
 */
export func resolve(base as string, href as string) {
    return resolveIn($base, $href);
}

# --- the table of contents -----------------------------------------------

# The EPUB 3 table of contents: the `<nav epub:type="toc">` of the navigation
# document, read as HTML so an entity or a stray tag does not lose it.
# What the navigation document holds: its table of contents, landmarks and
# page list.
def struct NavRead {
    toc as list of TocEntry,
    landmarks as list of Landmark,
    pages as list of PageTarget
};

# The `<nav>` with this `epub:type`, -1 for none.
func navOf(navs as list of html.Node, kind as string) {
    for (def i in 0..len($navs)) {
        if (hasProperty(attrValue($navs[$i], "epub:type"), $kind)) {
            return $i;
        }
    }
    return -1;
}

# The first `<ol>` directly in a node, or an empty element.
func firstList(n as html.Node) {
    for (def ol in $n.children) {
        if ($ol.kind == html.NodeKind.Element and $ol.tag == "ol") {
            return $ol;
        }
    }
    return html.Node{kind: html.NodeKind.Element, tag: "ol", attrs: [], children: [], text: ""};
}

# The links of a flat `<ol>` (landmarks, a page list), in order: each
# item's first `<a>` with its `epub:type`, label and resolved href.
func navLinks(ol as html.Node, base as string) {
    def out as list of Landmark;
    for (def li in $ol.children) {
        if ($li.kind != html.NodeKind.Element or $li.tag != "li") {
            continue;
        }
        for (def a in findTags($li, "a", [])) {
            if (attrValue($a, "href") != "") {
                $out[] = Landmark{
                    type: attrValue($a, "epub:type"),
                    title: inlineText($a),
                    href: resolveIn($base, attrValue($a, "href"))
                };
            }
            break;
        }
    }
    return $out;
}

# The EPUB 3 navigation document, read as HTML so an entity or a stray tag
# does not lose it: the `<nav epub:type="toc">`, the landmarks and the page
# list.
func navRead(source as string, base as string) {
    def out as NavRead init NavRead{toc: [], landmarks: [], pages: []};
    def doc as html.Node init parseHtml($source);
    def navs as list of html.Node init findTags($doc, "nav", []);
    def at as int init navOf($navs, "toc");
    if ($at >= 0) {
        $out.toc = navItems(firstList($navs[$at]), 0, $base, []);
    }
    $at = navOf($navs, "landmarks");
    if ($at >= 0) {
        $out.landmarks = navLinks(firstList($navs[$at]), $base);
    }
    $at = navOf($navs, "page-list");
    if ($at >= 0) {
        for (def l in navLinks(firstList($navs[$at]), $base)) {
            $out.pages[] = PageTarget{label: $l.title, href: $l.href};
        }
    }
    return $out;
}

# The entries of one `<ol>` and the lists nested in its items: recursion to
# RECURSION_DEPTH (it borrows the nodes), then an explicit stack (the tiny
# build allows 120 nested calls).
func navItems(ol as html.Node, level as int, base as string, acc as list of TocEntry) {
    return navItemsAt($ol, $level, $base, $acc, 0);
}

func navItemsAt(
    ol as html.Node,
    level as int,
    base as string,
    acc as list of TocEntry,
    depth as int) {
    for (def li in $ol.children) {
        if ($li.kind != html.NodeKind.Element or $li.tag != "li") {
            continue;
        }
        def labelled as bool init false;
        for (def c in $li.children) {
            if ($c.kind != html.NodeKind.Element) {
                continue;
            }
            if (not $labelled and ($c.tag == "a" or $c.tag == "span")) {
                def href as string init "";
                if ($c.tag == "a" and attrValue($c, "href") != "") {
                    $href = resolveIn($base, attrValue($c, "href"));
                }
                $labelled = true;
                $acc[] = TocEntry{title: inlineText($c), href: $href, level: $level};
            } elseif ($c.tag == "ol" and $labelled) {
                if ($depth + 1 < RECURSION_DEPTH) {
                    $acc = navItemsAt($c, $level + 1, $base, $acc, $depth + 1);
                } else {
                    $acc = navItemsDeep($c, $level + 1, $base, $acc);
                }
            }
        }
    }
    return $acc;
}

# `navItems` past RECURSION_DEPTH, with an explicit stack.
func navItemsDeep(ol as html.Node, level as int, base as string, acc as list of TocEntry) {
    # One frame per open `<ol>` or `<li>`: the node, the next child to look
    # at, its level, whether it is an `<li>` and whether that has its label.
    def nodes as list of html.Node init [$ol];
    def next as list of int init [0];
    def levels as list of int init [$level];
    def isItem as list of bool init [false];
    def labelled as list of bool init [false];
    def top as int init 0;
    while ($top >= 0) {
        def i as int init $next[$top];
        if ($i >= len($nodes[$top].children)) {
            $top = $top - 1;
            continue;
        }
        $next[$top] = $i + 1;
        def c as html.Node init $nodes[$top].children[$i];
        if ($c.kind != html.NodeKind.Element) {
            continue;
        }
        def push as bool init false;
        def pushLevel as int init $levels[$top];
        def pushItem as bool init false;
        if (not $isItem[$top]) {
            if ($c.tag == "li") {
                $push = true;
                $pushItem = true;
            }
        } elseif (not $labelled[$top] and ($c.tag == "a" or $c.tag == "span")) {
            def href as string init "";
            if ($c.tag == "a" and attrValue($c, "href") != "") {
                $href = resolveIn($base, attrValue($c, "href"));
            }
            $labelled[$top] = true;
            $acc[] = TocEntry{title: inlineText($c), href: $href, level: $levels[$top]};
        } elseif ($c.tag == "ol" and $labelled[$top]) {
            $push = true;
            $pushLevel = $levels[$top] + 1;
        }
        if ($push) {
            $top = $top + 1;
            if ($top < len($nodes)) {
                $nodes[$top] = $c;
                $next[$top] = 0;
                $levels[$top] = $pushLevel;
                $isItem[$top] = $pushItem;
                $labelled[$top] = false;
            } else {
                $nodes[] = $c;
                $next[] = 0;
                $levels[] = $pushLevel;
                $isItem[] = $pushItem;
                $labelled[] = false;
            }
        }
    }
    return $acc;
}

# The EPUB 2 table of contents, toc.ncx: XML, read strictly.
func ncxToc(root as xml.Value, path as string, base as string) {
    def out as list of TocEntry;
    if (not xml.has($root, "*:navMap")) {
        fail("toc", shown($path) + " has no navMap");
    }
    return ncxEntries(xml.get($root, "*:navMap"), 0, $base, $out);
}

# The NCX `<pageList>`: each `<pageTarget>`'s label and target.
func ncxPages(root as xml.Value, base as string) {
    def out as list of PageTarget;
    if (not xml.has($root, "*:pageList")) {
        return $out;
    }
    for (def t in xml.findAll(xml.get($root, "*:pageList"), "*:pageTarget")) {
        if (xml.has($t, "*:content") and xml.hasAttr(xml.get($t, "*:content"), "src")) {
            $out[] = PageTarget{
                label: firstText($t, "*:navLabel/*:text", {}),
                href: resolveIn($base, xml.attr(xml.get($t, "*:content"), "src"))
            };
        }
    }
    return $out;
}

func ncxEntries(parent as xml.Value, level as int, base as string, acc as list of TocEntry) {
    # One frame per open level: its navPoints and the next one to read.
    def points as list of list of xml.Value init [xml.findAll($parent, "*:navPoint")];
    def next as list of int init [0];
    def top as int init 0;
    while ($top >= 0) {
        def i as int init $next[$top];
        if ($i >= len($points[$top])) {
            $top = $top - 1;
            continue;
        }
        $next[$top] = $i + 1;
        def point as xml.Value init $points[$top][$i];
        def href as string init "";
        if (xml.has($point, "*:content")) {
            def content as xml.Value init xml.get($point, "*:content");
            if (xml.hasAttr($content, "src")) {
                $href = resolveIn($base, xml.attr($content, "src"));
            }
        }
        $acc[] = TocEntry{
            title: firstText($point, "*:navLabel/*:text", {}),
            href: $href,
            level: $level + $top
        };
        $top = $top + 1;
        if ($top < len($points)) {
            $points[$top] = xml.findAll($point, "*:navPoint");
            $next[$top] = 0;
        } else {
            $points[] = xml.findAll($point, "*:navPoint");
            $next[] = 0;
        }
    }
    return $acc;
}

# --- chapters ------------------------------------------------------------

# Media types of documents that hold text. Anything else in the spine (a
# picture, in a fixed-layout book) is a "foreign" item.
def const DOCUMENT_TYPES as list of string init [
    "application/xhtml+xml",
    "image/svg+xml",
    "text/html",
    "application/x-dtbook+xml",
    "text/x-oeb1-document"
];

func isDocument(mediaType as string) {
    return lists.contains(DOCUMENT_TYPES, strings.lower($mediaType));
}

# A content document as a Chapter. A foreign spine item is a chapter with no
# content; its bytes stay among the resources. Whether the `xml` parser accepts it is
# recorded; its title is read with whichever parser does.
def struct ChapterRead {
    chapter as Chapter,
    note as string
};

func chapterOf(a as Archive, item as Item, linear as bool, spineProps as string) {
    if (not isDocument($item.mediaType)) {
        return ChapterRead{
            note: "",
            chapter: Chapter{
                id: $item.id,
                href: $item.href,
                title: "",
                mediaType: $item.mediaType,
                properties: $item.properties,
                content: "",
                linear: $linear,
                wellFormed: false,
                spineProperties: $spineProps,
                mediaOverlay: $item.mediaOverlay
            }
        };
    }
    def decoded as Decoded init documentText($a, $item.path, "content", true);
    def content as string init $decoded.text;
    def ok as bool init true;
    def title as string init "";
    try {
        def doc as xml.Value init xml.decode($content);
        if (xml.has($doc, "*:head/*:title")) {
            $title = strings.trim(xml.text(xml.get($doc, "*:head/*:title")));
        }
    } catch (e) {
        # A cap of the `xml` parser (its nesting, 1000 levels, 64 on the tiny
        # build) does not refuse the book: the chapter is read as HTML, whose
        # parser has caps of its own, as for a chapter that is not XML.
        if ($e.kind != "limit" and isGeneric($e.kind)) {
            throw $e;
        }
        $ok = false;
    }
    if (not $ok) {
        for (def t in findTags(parseHtml($content), "title", [])) {
            $title = inlineText($t);
            break;
        }
    }
    return ChapterRead{
        note: $decoded.note,
        chapter: Chapter{
            id: $item.id,
            href: $item.href,
            title: $title,
            mediaType: $item.mediaType,
            properties: $item.properties,
            content: $content,
            linear: $linear,
            wellFormed: $ok,
            spineProperties: $spineProps,
            mediaOverlay: $item.mediaOverlay
        }
    };
}

# The metadata of the package document as a Book with no content yet.
func metadataOf(pkg as xml.Value, ns as map of string to string) {
    def version as string init requiredAttr($pkg, "version", "the package");
    def uidRef as string init requiredAttr($pkg, "unique-identifier", "the package");
    if (not xml.has($pkg, "o:metadata", $ns)) {
        fail("package", "the package document has no metadata");
    }
    def meta as xml.Value init xml.get($pkg, "o:metadata", $ns);
    def uid as string init "";
    for (def node in xml.findAll($meta, "dc:identifier", $ns)) {
        if (xml.hasAttr($node, "id") and xml.attr($node, "id") == $uidRef) {
            $uid = strings.trim(xml.text($node));
        }
    }
    if ($uid == "") {
        fail("package", "the unique identifier " + shown($uidRef) + " is missing or empty");
    }
    def b as Book init Book{
        title: requiredText($meta, "dc:title", $ns, "title"),
        lang: requiredText($meta, "dc:language", $ns, "language"),
        identifier: $uid,
        authors: [],
        description: firstText($meta, "dc:description", $ns),
        publisher: firstText($meta, "dc:publisher", $ns),
        date: firstText($meta, "dc:date", $ns),
        modified: "",
        version: $version,
        cover: "",
        chapters: [],
        toc: [],
        resources: [],
        ncx: false,
        direction: "",
        compress: false,
        layout: "",
        orientation: "",
        spread: "",
        flow: "",
        viewport: "",
        landmarks: [],
        pages: [],
        mediaMeta: [],
        notes: []
    };
    for (def node in xml.findAll($meta, "dc:creator", $ns)) {
        def name as string init strings.trim(xml.text($node));
        if ($name != "") {
            $b.authors[] = $name;
        }
    }
    for (def node in xml.findAll($meta, "o:meta", $ns)) {
        if (xml.hasAttr($node, "property") and
            strings.startsWith(xml.attr($node, "property"), "media:")) {
            $b.mediaMeta[] = Meta{
                property: xml.attr($node, "property"),
                refines: attrOr($node, "refines"),
                value: strings.trim(xml.text($node))
            };
            continue;
        }
        if (not xml.hasAttr($node, "property") or xml.hasAttr($node, "refines")) {
            continue;
        }
        def property as string init xml.attr($node, "property");
        def value as string init strings.trim(xml.text($node));
        if ($property == "dcterms:modified") {
            $b.modified = $value;
        } elseif ($property == "rendition:layout") {
            $b.layout = $value;
        } elseif ($property == "rendition:orientation") {
            $b.orientation = $value;
        } elseif ($property == "rendition:spread") {
            $b.spread = $value;
        } elseif ($property == "rendition:flow") {
            $b.flow = $value;
        }
    }
    return $b;
}

# Every dc:identifier, for the Adobe font key.
func identifiersOf(pkg as xml.Value, ns as map of string to string) {
    def out as list of string;
    for (def node in xml.findAll($pkg, "o:metadata/dc:identifier", $ns)) {
        $out[] = strings.trim(xml.text($node));
    }
    return $out;
}

# The manifest id an EPUB 2 `<meta name="cover">` names, "" for none.
# An attribute of an XML element, "" when it has none.
func attrOr(node as xml.Value, name as string) {
    if (xml.hasAttr($node, $name)) {
        return xml.attr($node, $name);
    }
    return "";
}

func coverMetaOf(pkg as xml.Value, ns as map of string to string) {
    for (def node in xml.findAll($pkg, "o:metadata/o:meta", $ns)) {
        if (xml.hasAttr($node, "name") and xml.attr($node, "name") == "cover" and
            xml.hasAttr($node, "content")) {
            return xml.attr($node, "content");
        }
    }
    return "";
}

# The chapters, in spine order.
# The media types a spine item may have without a fallback: XHTML and SVG
# content documents (EPUB 3 core media types for the spine).
func isCore(mediaType as string) {
    def t as string init strings.lower($mediaType);
    return $t == XHTML_TYPE or $t == "image/svg+xml";
}

# The first item with a core media type down an item's `fallback` chain. A
# chain that loops, names an item the manifest lacks, or ends without one is
# refused.
func fallbackOf(m as Manifest, byId as map of string to int, item as Item) {
    def seen as map of string to bool init {$item.id: true};
    def at as Item init $item;
    while (not isCore($at.mediaType)) {
        def next as string init $at.fallback;
        if ($next == "" or not maps.has($byId, $next)) {
            fail(
                "package",
                "the fallback chain of spine item " + shown($item.id) +
                    " ends without an XHTML or SVG document");
        }
        if (maps.has($seen, $next)) {
            fail(
                "package",
                "the fallback chain of spine item " + shown($item.id) + " loops at " + shown($next));
        }
        $seen[$next] = true;
        $at = $m.items[$byId[$next]];
    }
    return $at;
}

# The chapters, in spine order, and the notes their decoding left.
def struct Spine {
    chapters as list of Chapter,
    notes as list of string
};

func spineOf(
    a as Archive,
    spine as xml.Value,
    m as Manifest,
    byId as map of string to int,
    ns as map of string to string) {
    def refs as list of xml.Value init xml.findAll($spine, "o:itemref", $ns);
    if (len($refs) == 0) {
        fail("package", "the spine is empty");
    }
    def out as Spine init Spine{chapters: [], notes: []};
    def used as map of string to bool;
    for (def ref in $refs) {
        def idref as string init requiredAttr($ref, "idref", "a spine itemref");
        if (maps.has($m.missing, $idref)) {
            fail(
                "package",
                "spine item " + shown($idref) + " names a file that is not in the archive");
        }
        if (not maps.has($byId, $idref)) {
            fail("package", "spine item " + shown($idref) + " is not in the manifest");
        }
        def linear as bool init not (xml.hasAttr($ref, "linear") and
            xml.attr($ref, "linear") == "no");
        def spineProps as string init "";
        if (xml.hasAttr($ref, "properties")) {
            $spineProps = strings.trim(xml.attr($ref, "properties"));
        }
        def item as Item init $m.items[$byId[$idref]];
        # A picture stays a picture (a page of a comic, which `build` wraps
        # in a page of its own): its fallback is usually one generic page
        # shared by all of them. Any other type that is no XHTML or SVG
        # document is replaced by the first document down its chain, unless
        # that one is in the spine already.
        if (not isCore($item.mediaType) and not isImage($item.mediaType) and $item.fallback != "") {
            def core as Item init fallbackOf($m, $byId, $item);
            if (maps.has($used, $core.id)) {
                $out.notes[] = "spine item " + shown($idref) + " is " + $item.mediaType +
                    "; its fallback " + shown($core.id) +
                    " is in the spine already, so it is kept as it is";
            } else {
                $out.notes[] = "spine item " + shown($idref) + " is " + $item.mediaType +
                    "; read its fallback " + shown($core.id) + " (" + $core.mediaType + ")";
                $item = $core;
            }
        }
        $used[$item.id] = true;
        def got as ChapterRead init chapterOf($a, $item, $linear, $spineProps);
        $out.chapters[] = $got.chapter;
        if ($got.note != "") {
            $out.notes[] = $got.note;
        }
    }
    return $out;
}

# The ids of the chapters with text: their bytes are the chapter's content,
# not a resource. A map, so the manifest is not scanned once per item.
func spineDocuments(chapters as list of Chapter) {
    def out as map of string to bool;
    for (def i in 0..len($chapters)) {
        if (isDocument($chapters[$i].mediaType)) {
            $out[$chapters[$i].id] = true;
        }
    }
    return $out;
}

# Each chapter's title from the table of contents: the first entry whose
# target is in it, fragment or not. One pass over the entries, not one per
# chapter.
func tocTitles(toc as list of TocEntry) {
    def out as map of string to string;
    for (def i in 0..len($toc)) {
        if ($toc[$i].title == "") {
            continue;
        }
        def path as string init splitFragment($toc[$i].href)[0];
        if (not maps.has($out, $path)) {
            $out[$path] = $toc[$i].title;
        }
    }
    return $out;
}

# Whether a chapter links to this href (a fragment or not). A chapter that
# does not even contain the file's name is skipped without a parse.
func linkedFrom(chapters as list of Chapter, href as string) {
    def name as string init $href;
    def slash as int init strings.lastIndexOf($name, "/");
    if ($slash >= 0) {
        $name = $name[$slash + 1..];
    }
    for (def i in 0..len($chapters)) {
        if (not strings.contains($chapters[$i].content, $name)) {
            continue;
        }
        for (def m in regex.findAll(LINK_ATTR, $chapters[$i].content)) {
            def link as string init attrText($m);
            if ($link == "" or regex.matches(SCHEME, $link)) {
                continue;
            }
            def target as string init "";
            try {
                $target = resolveIn($chapters[$i].href, $link);
            } catch (e) {
                if ($e.kind != ERROR_KIND) {
                    throw $e;
                }
                continue;
            }
            if (splitFragment($target)[0] == $href) {
                return true;
            }
        }
    }
    return false;
}

# EPUB 2 `<guide>` types and the EPUB 3 structural semantics they stand for.
def const GUIDE_TYPES as map of string to string init {
    "text": "bodymatter",
    "title-page": "titlepage",
    "acknowledgements": "acknowledgments",
    "notes": "endnotes"
};

# The landmarks of an EPUB 2 `<guide>`, types mapped where EPUB 3 names
# them differently.
func guideOf(pkg as xml.Value, ns as map of string to string) {
    def out as list of Landmark;
    for (def ref in xml.findAll($pkg, "o:guide/o:reference", $ns)) {
        if (not xml.hasAttr($ref, "href") or not xml.hasAttr($ref, "type")) {
            continue;
        }
        def kind as string init xml.attr($ref, "type");
        if (maps.has(GUIDE_TYPES, strings.lower($kind))) {
            $kind = GUIDE_TYPES[strings.lower($kind)];
        }
        def title as string init "";
        if (xml.hasAttr($ref, "title")) {
            $title = xml.attr($ref, "title");
        }
        $out[] = Landmark{
            type: $kind,
            title: $title,
            href: resolveIn("package", xml.attr($ref, "href"))
        };
    }
    return $out;
}

# A fixed-layout page's `<meta name="viewport">`, as written in its head.
def const VIEWPORT_META as string init '(?i)<meta\s[^>]*name\s*=\s*["' + "']viewport[" + '"' +
    "'][^>]*>";
def const CONTENT_ATTR as string init '(?i)\scontent\s*=\s*(?:"([^"]*)"|' + "'([^']*)')";

# The viewport of the first chapter that declares one, "" for none.
func viewportOf(chapters as list of Chapter) {
    for (def i in 0..len($chapters)) {
        def m as regex.Match init regex.find(VIEWPORT_META, $chapters[$i].content);
        if ($m.start >= 0) {
            def c as regex.Match init regex.find(CONTENT_ATTR, $m.text);
            if ($c.start >= 0) {
                return attrText($c);
            }
        }
    }
    return "";
}

# The table of contents and the items it came from.
def struct TocFound {
    entries as list of TocEntry,
    landmarks as list of Landmark,
    pages as list of PageTarget,
    navId as string,
    ncxId as string,
    notes as list of string
};

# The table of contents: the EPUB 3 navigation document first, then the NCX
# the spine names (or any NCX in the manifest).
func tocFrom(a as Archive, spine as xml.Value, m as Manifest) {
    def items as list of Item init $m.items;
    def out as TocFound init TocFound{
        entries: [],
        landmarks: [],
        pages: [],
        navId: "",
        ncxId: "",
        notes: []
    };
    if (xml.hasAttr($spine, "toc")) {
        $out.ncxId = xml.attr($spine, "toc");
        if (maps.has($m.missing, $out.ncxId)) {
            $out.ncxId = "";
        } elseif (itemIndex($items, $out.ncxId) < 0) {
            fail("package", "the spine's toc " + shown($out.ncxId) + " is not in the manifest");
        }
    }
    for (def it in $items) {
        if ($out.navId == "" and hasProperty($it.properties, "nav")) {
            $out.navId = $it.id;
        }
        if ($out.ncxId == "" and $it.mediaType == NCX_TYPE) {
            $out.ncxId = $it.id;
        }
    }
    if ($out.navId != "") {
        def nav as Item init $items[itemIndex($items, $out.navId)];
        def d as Decoded init documentText($a, $nav.path, "toc", true);
        if ($d.note != "") {
            $out.notes[] = $d.note;
        }
        def got as NavRead init navRead($d.text, $nav.href);
        $out.entries = $got.toc;
        $out.landmarks = $got.landmarks;
        $out.pages = $got.pages;
    }
    if (len($out.entries) == 0 and $out.ncxId != "") {
        def ncx as Item init $items[itemIndex($items, $out.ncxId)];
        def x as XmlRead init declaredXml($a, $ncx.path, "toc");
        if ($x.note != "") {
            $out.notes[] = $x.note;
        }
        $out.entries = ncxToc($x.root, $ncx.path, $ncx.href);
        if (len($out.pages) == 0) {
            $out.pages = ncxPages($x.root, $ncx.href);
        }
    }
    return $out;
}

/**
 * Read an EPUB 2 or 3 book with the default caps (see `readWith`).
 *
 * @param data {bytes} the EPUB file
 * @return {Book} its metadata, chapters in reading order, table of contents
 *   and other files
 * @throws {EpubError} kind "epub" (see `readWith`)
 * @throws {Error} kind "limit" past a cap
 * @example
 *   def b as epub.Book init epub.read(fs.readBytes("book.epub"));
 *   for (def c in $b.chapters) {
 *       io.printf("%s\n", $c.title);
 *   }
 */
export func read(data as bytes) {
    return readWith($data, readOptions());
}

/**
 * Read an EPUB 2 or 3 book. The archive is unpacked with `archive`'s
 * zip-slip checks and the caps in `opts`; `META-INF/container.xml` leads to
 * the package document, whose metadata, manifest and spine make the `Book`.
 * The table of contents comes from the EPUB 3 navigation document, else from
 * the EPUB 2 `toc.ncx`. A chapter's title is its table of contents entry,
 * else its `<title>`. Obfuscated fonts (IDPF and Adobe) are restored.
 *
 * The container and the package are read strictly; a chapter that is not
 * well-formed XML is kept as it is and read as HTML (`wellFormed` false).
 * A few common faults are tolerated, each recorded as a line of the book's
 * `notes`: a `mimetype` deflated, not first or followed by whitespace; a
 * chapter, navigation document, package document or NCX in an ISO-8859 or
 * Windows charset it declares; a manifest item missing from the archive
 * (left out); a manifest href matching an archive name only when case is
 * ignored. A manifest href starting with `/` is from the container root.
 *
 * @param data {bytes} the EPUB file
 * @param opts {ReadOptions} the caps, from `readOptions()`
 * @return {Book} the book
 * @throws {EpubError} reason "archive" for a file that is not a zip or holds
 *   an unsafe name; "container" for a missing `mimetype`, one with other
 *   content, or a bad container document; "package" for a package document
 *   without a title, language, identifier, manifest or spine, with a spine
 *   item whose file is missing, or with an href that matches several archive
 *   names when case is ignored; "drm" for a DRM-protected book; "content"
 *   for a chapter neither UTF-8, UTF-16 nor in a declared legacy charset;
 *   "toc" for an unreadable `toc.ncx`
 * @throws {Error} kind "limit" for a file, an entry, the unpacked total or
 *   the entry count past its cap
 */
export func readWith(data as bytes, opts as ReadOptions) {
    def maxBytes as int init capOf($opts.maxBytes, DEFAULT_MAX_BYTES);
    if (len($data) > $maxBytes) {
        throw Error{
            kind: "limit",
            message: "epub: the file is larger than " + convert.toString($maxBytes) + " bytes"
        };
    }
    checkZip($data);
    def a as Archive init unpack($data, $opts);
    def methods as map of string to int init entryMethods($data);
    def notes as list of string;
    def mime as string init mimetypeNote($data, $a, $methods);
    if ($mime != "") {
        $notes[] = $mime;
    }
    def obfuscated as map of string to string init protection($a);
    def opfPath as string init rootfileOf($a);
    def opf as XmlRead init declaredXml($a, $opfPath, "package");
    if ($opf.note != "") {
        $notes[] = $opf.note;
    }
    def pkg as xml.Value init $opf.root;
    if (xml.localName($pkg) != "package" or xml.namespace($pkg) != OPF_NS) {
        fail("package", shown($opfPath) + " is not an OPF package document");
    }
    def ns as map of string to string init {"o": OPF_NS, "dc": DC_NS};
    def b as Book init metadataOf($pkg, $ns);
    def m as Manifest init manifestOf($a, $pkg, dirOf($opfPath), $ns);
    def items as list of Item init $m.items;
    $notes = lists.concat($notes, $m.notes);
    if (not xml.has($pkg, "o:spine", $ns)) {
        fail("package", "the package document has no spine");
    }
    def spine as xml.Value init xml.get($pkg, "o:spine", $ns);
    def byId as map of string to int;
    for (def i in 0..len($items)) {
        $byId[$items[$i].id] = $i;
    }
    def read as Spine init spineOf($a, $spine, $m, $byId, $ns);
    $b.chapters = $read.chapters;
    $notes = lists.concat($notes, $read.notes);
    if (xml.hasAttr($spine, "page-progression-direction")) {
        def ppd as string init xml.attr($spine, "page-progression-direction");
        if ($ppd == "ltr" or $ppd == "rtl") {
            $b.direction = $ppd;
        }
    }
    $b.compress = deflatedEntries($methods);
    def found as TocFound init tocFrom($a, $spine, $m);
    $notes = lists.concat($notes, $found.notes);
    $b.toc = $found.entries;
    $b.landmarks = $found.landmarks;
    if (len($b.landmarks) == 0) {
        $b.landmarks = guideOf($pkg, $ns);
    }
    $b.pages = $found.pages;
    $b.ncx = $found.ncxId != "";
    def titles as map of string to string init tocTitles($b.toc);
    for (def i in 0..len($b.chapters)) {
        if (maps.has($titles, $b.chapters[$i].href)) {
            $b.chapters[$i].title = $titles[$b.chapters[$i].href];
        }
    }
    # The cover: the EPUB 3 property, else the EPUB 2 meta.
    for (def it in $items) {
        if ($b.cover == "" and hasProperty($it.properties, "cover-image")) {
            $b.cover = $it.href;
        }
    }
    def coverMeta as string init coverMetaOf($pkg, $ns);
    if ($b.cover == "" and $coverMeta != "") {
        def at as int init itemIndex($items, $coverMeta);
        if ($at >= 0 and
            (isImage($items[$at].mediaType) or maps.has(spineDocuments($b.chapters), $coverMeta))) {
            $b.cover = $items[$at].href;
        }
    }
    def inSpine as map of string to bool init spineDocuments($b.chapters);
    def navLinked as bool init $found.navId != "" and not maps.has($inSpine, $found.navId) and
        linkedFrom($b.chapters, $items[itemIndex($items, $found.navId)].href);
    for (def it in $items) {
        if (maps.has($inSpine, $it.id) or $it.id == $found.ncxId) {
            continue;
        }
        # The navigation document is the book's table of contents, which
        # `toc` stands for; it is kept as a file only when a chapter links
        # into it (an index pointing at its entries), so the links still
        # lead somewhere when the book is written again.
        if ($it.id == $found.navId and not $navLinked) {
            continue;
        }
        # The bytes go straight into the Resource: bound to a variable first,
        # every file of the book was copied once more.
        $b.resources[] = Resource{
            id: $it.id,
            href: $it.href,
            mediaType: $it.mediaType,
            properties: $it.properties,
            data: entryData($a, $it.path)
        };
        if (maps.has($obfuscated, $it.path)) {
            def last as int init len($b.resources) - 1;
            $b.resources[$last].data = deobfuscate(
                $b.resources[$last].data,
                $obfuscated[$it.path],
                $b.identifier,
                identifiersOf($pkg, $ns));
        }
    }
    $b.viewport = viewportOf($b.chapters);
    # Landmarks that are exactly the ones `build` generates for this book
    # read back as none, so a book the builders made (which has none) reads
    # back equal; `build` generates the same ones again.
    if (len($b.landmarks) > 0 and $b.landmarks == generatedLandmarks($b)) {
        $b.landmarks = [];
    }
    $b.notes = $notes;
    return $b;
}

/**
 * A file of the book by its href (a `#fragment` is ignored).
 *
 * @param b {Book} the book
 * @param href {string} the file's href, relative to the package document
 * @return {Resource} the file
 * @throws {EpubError} reason "missing" when the book has no such file
 * @example
 *   def c as epub.Resource init epub.resource($b, $b.cover);
 */
export func resource(b as Book, href as string) {
    def want as string init cleanPath(splitFragment($href)[0]);
    for (def r in $b.resources) {
        if ($r.href == $want) {
            return $r;
        }
    }
    fail("missing", "the book has no file " + shown($href));
    return Resource{id: "", href: "", mediaType: "", properties: "", data: bytesOf("")};
}
