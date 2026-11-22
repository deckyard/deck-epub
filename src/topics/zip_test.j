# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# epub - white-box tests for the zip writer (ported from Grimoire's). The
# archive is written by hand, so the byte order, the checksum and the stored
# first entry are tested against fixed values, not against the code that made
# them. Spliced into epub_test.j via include.

func testLittleEndianFieldsAreWrittenLowByteFirst() {
    def small as bytes init le16(0x0201);
    testing.assertEqual(len($small), 2);
    testing.assertEqual($small[0], 1);
    testing.assertEqual($small[1], 2);
    def wide as bytes init le32(0x04030201);
    testing.assertEqual(len($wide), 4);
    testing.assertEqual($wide[0], 1);
    testing.assertEqual($wide[3], 4);
}

# The check value every crc32 implementation is published with.
func testTheChecksumMatchesTheKnownCheckValue() {
    testing.assertEqual(crcOf(bytesOf("123456789")), 0xcbf43926);
    testing.assertEqual(crcOf(bytesOf("")), 0);
}

func testTheArchiveOpensWithAStoredMimetype() {
    def z as bytes init zipOf(
        [
            File{name: "mimetype", data: bytesOf(MIMETYPE)},
            File{name: "OEBPS/style.css", data: bytesOf(CSS)}
        ],
        false);
    testing.assertTrue(binary.startsWith($z, le32(0x04034b50)));
    # Bytes 8 and 9 are the compression method: 0 is stored, 8 is deflate.
    testing.assertEqual($z[8], 0);
    testing.assertEqual($z[9], 0);
    testing.assertEqual(textOf($z[30..38]), "mimetype");
    testing.assertEqual(textOf($z[38..38 + len(MIMETYPE)]), MIMETYPE);
}

# Stored, not deflated, for every entry: a payload that would certainly
# compress is in the archive verbatim.
func testEntriesAreNotCompressed() {
    def payload as string init strings.replicate("a", 400);
    def z as bytes init zipOf([File{name: "long.txt", data: bytesOf($payload)}], false);
    testing.assertTrue(binary.contains($z, bytesOf($payload)));
}

func testTheDirectoryCountsEveryEntry() {
    def z as bytes init zipOf(
        [
            File{name: "a", data: bytesOf("1")},
            File{name: "b", data: bytesOf("2")},
            File{name: "c", data: bytesOf("3")}
        ],
        false);
    def end as int init len($z) - 22;
    testing.assertTrue(binary.startsWith($z[$end..len($z)], le32(0x06054b50)));
    testing.assertEqual($z[$end + 10], 3);
}

# The archive is a zip other readers take: `archive.unpack` gets every entry
# back, in order and intact.
func testTheArchiveUnpacksWithTheArchiveLibrary() {
    def z as bytes init zipOf(
        [
            File{name: "mimetype", data: bytesOf(MIMETYPE)},
            File{name: "a/b.txt", data: bytesOf("hello")},
            File{name: "empty", data: bytesOf("")}
        ],
        false);
    def back as list of archive.Entry init archive.unpack("zip", $z);
    testing.assertEqual(len($back), 3);
    testing.assertEqual($back[0].name, "mimetype");
    testing.assertEqual($back[1].name, "a/b.txt");
    testing.assertEqual(textOf($back[1].data), "hello");
    testing.assertEqual(len($back[2].data), 0);
}
