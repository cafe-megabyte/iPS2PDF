#!/usr/bin/env python3
"""Generate the deterministic, publishable iPS2PDF signature-font dummy.

The font has one mapped glyph: U+201A. Its outline is a geometric X assembled
from coordinates in this file and contains no data derived from a private font.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


POSTSCRIPT_NAME = "AAAAAC+SignatureFont-Book"
FAMILY_NAME = "iPS2PDF Signature Dummy"
FULL_NAME = "iPS2PDF Signature Dummy Book"
MAGIC_CHECKSUM = 0xB1B0AFBA


def u16(value: int) -> bytes:
    return struct.pack(">H", value & 0xFFFF)


def s16(value: int) -> bytes:
    return struct.pack(">h", value)


def u32(value: int) -> bytes:
    return struct.pack(">I", value & 0xFFFFFFFF)


def checksum(data: bytes) -> int:
    padded = data + bytes((-len(data)) % 4)
    return sum(struct.unpack(f">{len(padded) // 4}I", padded)) & 0xFFFFFFFF


def cff_index(values: list[bytes]) -> bytes:
    if not values:
        return u16(0)
    offsets = [1]
    for value in values:
        offsets.append(offsets[-1] + len(value))
    maximum = offsets[-1]
    off_size = max(1, (maximum.bit_length() + 7) // 8)
    encoded = bytearray(u16(len(values)))
    encoded.append(off_size)
    for offset in offsets:
        encoded.extend(offset.to_bytes(off_size, "big"))
    for value in values:
        encoded.extend(value)
    return bytes(encoded)


def cff_integer(value: int) -> bytes:
    if -107 <= value <= 107:
        return bytes([value + 139])
    if 108 <= value <= 1131:
        value -= 108
        return bytes([247 + value // 256, value % 256])
    if -1131 <= value <= -108:
        value = -value - 108
        return bytes([251 + value // 256, value % 256])
    if -32768 <= value <= 32767:
        return b"\x1c" + s16(value)
    return b"\x1d" + struct.pack(">i", value)


def type2_number(value: int) -> bytes:
    return cff_integer(value)


def dict_integer(value: int) -> bytes:
    if not -32768 <= value <= 32767:
        raise ValueError("Top DICT value exceeds ShortInt")
    return b"\x1c" + s16(value)


def dummy_charstring() -> bytes:
    # Three filled X contours approximate the private signature's 3.5:1 bounds
    # at the same point size. The first operand is the advance width.
    x_points = [
        (100, 0), (500, 400), (900, 0), (1000, 100), (600, 500),
        (1000, 900), (900, 1000), (500, 600), (100, 1000), (0, 900),
        (400, 500), (0, 100), (100, 0),
    ]
    contours = [[(x + offset, y) for x, y in x_points] for offset in (0, 1240, 2480)]
    result = bytearray(type2_number(3480))
    current = (0, 0)
    for contour in contours:
        first = contour[0]
        result.extend(type2_number(first[0] - current[0]))
        result.extend(type2_number(first[1] - current[1]))
        result.append(21)  # rmoveto starts another contour.
        current = first
        for point in contour[1:]:
            result.extend(type2_number(point[0] - current[0]))
            result.extend(type2_number(point[1] - current[1]))
            current = point
        result.append(5)  # rlineto consumes all coordinate pairs.
    result.append(14)  # endchar closes the contour.
    return bytes(result)


def build_cff() -> bytes:
    header = b"\x01\x00\x04\x04"
    names = cff_index([POSTSCRIPT_NAME.encode("ascii")])
    strings = cff_index([FULL_NAME.encode("ascii"), FAMILY_NAME.encode("ascii")])
    global_subroutines = cff_index([])
    charset = b"\x00" + u16(117)  # format 0, quotesinglbase SID
    charstrings = cff_index([b"\x0e", dummy_charstring()])

    # ShortInt encoding makes the Top DICT length independent of final offsets.
    def top_dictionary(charset_offset: int, charstrings_offset: int) -> bytes:
        result = bytearray()
        result.extend(dict_integer(391) + b"\x02")  # FullName
        result.extend(dict_integer(392) + b"\x03")  # FamilyName
        for value in (0, 0, 3480, 1000):
            result.extend(dict_integer(value))
        result.append(5)  # FontBBox
        result.extend(dict_integer(charset_offset) + b"\x0f")
        result.extend(dict_integer(charstrings_offset) + b"\x11")
        return bytes(result)

    placeholder = cff_index([top_dictionary(0, 0)])
    charset_offset = len(header) + len(names) + len(placeholder) + len(strings) + len(global_subroutines)
    charstrings_offset = charset_offset + len(charset)
    top = cff_index([top_dictionary(charset_offset, charstrings_offset)])
    assert len(top) == len(placeholder)
    return header + names + top + strings + global_subroutines + charset + charstrings


def build_cmap() -> bytes:
    # Microsoft Unicode BMP format 4 with U+201A -> glyph 1 and the sentinel.
    segment_count = 2
    subtable = b"".join([
        u16(4), u16(32), u16(0), u16(segment_count * 2), u16(4), u16(1), u16(0),
        u16(0x201A), u16(0xFFFF), u16(0),
        u16(0x201A), u16(0xFFFF),
        u16((1 - 0x201A) & 0xFFFF), u16(1),
        u16(0), u16(0),
    ])
    return u16(0) + u16(1) + u16(3) + u16(1) + u32(12) + subtable


def build_name() -> bytes:
    values = {
        1: FAMILY_NAME,
        2: "Book",
        3: "1.0;iPS2PDF;SignatureDummy",
        4: FULL_NAME,
        5: "Version 1.0",
        6: POSTSCRIPT_NAME,
    }
    records = []
    storage = bytearray()
    for name_id, value in sorted(values.items()):
        encoded = value.encode("utf-16-be")
        records.append(u16(3) + u16(1) + u16(0x0409) + u16(name_id) + u16(len(encoded)) + u16(len(storage)))
        storage.extend(encoded)
    return u16(0) + u16(len(records)) + u16(6 + 12 * len(records)) + b"".join(records) + bytes(storage)


def build_os2() -> bytes:
    panose = bytes([2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
    return b"".join([
        u16(4), s16(3480), u16(400), u16(5), u16(0),
        s16(650), s16(600), s16(0), s16(75),
        s16(650), s16(600), s16(0), s16(350),
        s16(50), s16(250), s16(0),
        panose,
        u32(0), u32(0), u32(0), u32(0), b"iPS2",
        u16(0x0040), u16(0x201A), u16(0x201A),
        s16(1000), s16(0), s16(200), u16(1000), u16(0),
        u32(0), u32(0), s16(500), s16(1000), u16(0), u16(0), u16(1),
    ])


def build_font() -> bytes:
    head = bytearray(b"".join([
        u32(0x00010000), u32(0x00010000), u32(0), u32(0x5F0F3CF5),
        u16(3), u16(1000), struct.pack(">q", 0), struct.pack(">q", 0),
        s16(0), s16(0), s16(3480), s16(1000), u16(0), u16(8),
        s16(2), s16(0), s16(0),
    ]))
    tables = {
        b"CFF ": build_cff(),
        b"OS/2": build_os2(),
        b"cmap": build_cmap(),
        b"head": bytes(head),
        b"hhea": b"".join([
            u32(0x00010000), s16(1000), s16(0), s16(200), u16(3480),
            s16(0), s16(0), s16(3480), s16(1), s16(0), s16(0),
            s16(0), s16(0), s16(0), s16(0), s16(0), u16(2),
        ]),
        b"hmtx": u16(500) + s16(0) + u16(3480) + s16(0),
        b"maxp": u32(0x00005000) + u16(2),
        b"name": build_name(),
        b"post": u32(0x00030000) + u32(0) + s16(-75) + s16(50) + u32(0) * 5,
    }
    tags = sorted(tables)
    count = len(tags)
    power = 1 << (count.bit_length() - 1)
    header = b"OTTO" + u16(count) + u16(power * 16) + u16(power.bit_length() - 1) + u16(count * 16 - power * 16)
    offset = 12 + 16 * count
    records = bytearray()
    payload = bytearray()
    offsets: dict[bytes, int] = {}
    for tag in tags:
        data = tables[tag]
        offsets[tag] = offset
        records.extend(tag + u32(checksum(data)) + u32(offset) + u32(len(data)))
        payload.extend(data)
        padding = (-len(data)) % 4
        payload.extend(bytes(padding))
        offset += len(data) + padding
    font = bytearray(header + records + payload)
    adjustment = (MAGIC_CHECKSUM - checksum(font)) & 0xFFFFFFFF
    struct.pack_into(">I", font, offsets[b"head"] + 8, adjustment)
    assert checksum(font) == MAGIC_CHECKSUM
    return bytes(font)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = build_font()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)


if __name__ == "__main__":
    main()
