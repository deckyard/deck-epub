# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# epub - the zip writer, ported from Grimoire's EPUB renderer.
#
# The `mimetype` entry has to come first and be stored, which `archive.pack`
# cannot express, so the zip is written here: local headers, central
# directory, end record. Entries are stored unless the book asks for
# compression: deflate makes a smaller file, but its output may change with
# the toolchain that runs it, and a stored archive is the same bytes on every
# interpreter.

# Every entry carries the same date, so two builds of the same book are the
# same file. 1980-01-01, the earliest a DOS timestamp can say.
def const DOS_TIME as int init 0;
def const DOS_DATE as int init 33;

# Without zip64 a count or a name's length is 16 bits and an offset or size 32.
def const ZIP_MAX_ENTRIES as int init 65535;
def const ZIP_MAX_NAME as int init 65535;
def const ZIP_MAX_BYTES as int init 4294967295;

# One file on its way into the archive.
def struct File {
    name as string,
    data as bytes
};

# `crc.compute` hands back the checksum big-endian; a zip field wants the number.
func crcOf(data as bytes) {
    return binary.readUint("be", crc.compute("crc32", $data), 0, 4);
}

# The general purpose flags of an entry: bit 11 says its name is UTF-8,
# set only for a name beyond ASCII, so an ASCII book keeps its bytes.
func flagsOf(name as string) {
    if (regex.matches('^[\x00-\x7F]*$', $name)) {
        return 0;
    }
    return 0x0800;
}

# The local header that precedes each entry: version 2.0, no flags, method
# 0 (stored) or 8 (deflated), the sizes packed and unpacked.
func localHeader(f as File, e as Packed) {
    def name as bytes init bytesOf($f.name);
    return binary.join([
        binary.fromUint("le", 0x04034b50, 4),
        binary.fromUint("le", 20, 2),
        binary.fromUint("le", flagsOf($f.name), 2),
        binary.fromUint("le", $e.method, 2),
        binary.fromUint("le", DOS_TIME, 2),
        binary.fromUint("le", DOS_DATE, 2),
        binary.fromUint("le", $e.sum, 4),
        binary.fromUint("le", len($e.data), 4),
        binary.fromUint("le", len($f.data), 4),
        binary.fromUint("le", len($name), 2),
        binary.fromUint("le", 0, 2),
        $name
    ]);
}

func centralHeader(f as File, e as Packed, offset as int) {
    def name as bytes init bytesOf($f.name);
    return binary.join([
        binary.fromUint("le", 0x02014b50, 4),
        binary.fromUint("le", 20, 2),
        binary.fromUint("le", 20, 2),
        binary.fromUint("le", flagsOf($f.name), 2),
        binary.fromUint("le", $e.method, 2),
        binary.fromUint("le", DOS_TIME, 2),
        binary.fromUint("le", DOS_DATE, 2),
        binary.fromUint("le", $e.sum, 4),
        binary.fromUint("le", len($e.data), 4),
        binary.fromUint("le", len($f.data), 4),
        binary.fromUint("le", len($name), 2),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", 0, 4),
        binary.fromUint("le", $offset, 4),
        $name
    ]);
}

# An entry as it goes into the archive: the method, the checksum of the
# unpacked bytes, and the bytes written.
def struct Packed {
    method as int,
    sum as int,
    data as bytes
};

# Raw deflate (zip method 8) when `deflate` is set and it makes the entry
# smaller; stored (method 0) otherwise.
func packed(f as File, deflate as bool) {
    def sum as int init crcOf($f.data);
    if ($deflate) {
        def small as bytes init compress.pack("deflate", $f.data, "best");
        if (len($small) < len($f.data)) {
            return Packed{method: 8, sum: $sum, data: $small};
        }
    }
    return Packed{method: 0, sum: $sum, data: $f.data};
}

# zipOf lays the files out: every entry, then the central directory, then the
# end record. The order of `files` is the order of the archive; `mimetype`
# being first is the caller's business, and so is leaving it stored: with
# `deflate` set, every entry but the first is deflated where that helps. A
# book too large for a zip without zip64 is a "limit" error.
func zipOf(files as list of File, deflate as bool) {
    if (len($files) > ZIP_MAX_ENTRIES) {
        throw Error{kind: "limit", message: "epub: more than 65535 files in one book"};
    }
    def body as list of bytes;
    def central as list of bytes;
    def offset as int init 0;
    for (def i in 0..len($files)) {
        if (len(bytesOf($files[$i].name)) > ZIP_MAX_NAME) {
            throw Error{kind: "limit", message: "epub: a file name longer than 65535 bytes"};
        }
        if (len($files[$i].data) > ZIP_MAX_BYTES) {
            throw Error{kind: "limit", message: "epub: the book is larger than 4 GiB"};
        }
        def e as Packed init packed($files[$i], $deflate and $i > 0);
        def header as bytes init localHeader($files[$i], $e);
        $body[] = $header;
        $body[] = $e.data;
        $central[] = centralHeader($files[$i], $e, $offset);
        $offset = $offset + len($header) + len($e.data);
        if ($offset > ZIP_MAX_BYTES) {
            throw Error{kind: "limit", message: "epub: the book is larger than 4 GiB"};
        }
    }
    def directory as bytes init binary.join($central);
    if (len($directory) > ZIP_MAX_BYTES) {
        throw Error{kind: "limit", message: "epub: the book is larger than 4 GiB"};
    }
    def end as bytes init binary.join([
        binary.fromUint("le", 0x06054b50, 4),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", 0, 2),
        binary.fromUint("le", len($files), 2),
        binary.fromUint("le", len($files), 2),
        binary.fromUint("le", len($directory), 4),
        binary.fromUint("le", $offset, 4),
        binary.fromUint("le", 0, 2)
    ]);
    $body[] = $directory;
    $body[] = $end;
    return binary.join($body);
}
