#!/usr/bin/env python3
"""Validate the narrow font contract used by PDF signature placement."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"Invalid signature font: {message}")


def tables(data: bytes) -> dict[bytes, bytes]:
    if len(data) < 12 or data[:4] != b"OTTO":
        fail("an OpenType/CFF font is required")
    count = struct.unpack_from(">H", data, 4)[0]
    if count == 0 or 12 + 16 * count > len(data):
        fail("invalid table directory")
    result = {}
    for index in range(count):
        tag, _, offset, length = struct.unpack_from(">4sIII", data, 12 + 16 * index)
        if offset > len(data) or length > len(data) - offset or tag in result:
            fail("invalid or duplicate table")
        result[tag] = data[offset:offset + length]
    return result


def cmap_codepoints(table: bytes) -> set[int]:
    if len(table) < 4:
        fail("invalid cmap")
    count = struct.unpack_from(">H", table, 2)[0]
    offsets = set()
    for index in range(count):
        record = 4 + 8 * index
        if record + 8 > len(table):
            fail("invalid cmap record")
        offset = struct.unpack_from(">I", table, record + 4)[0]
        if offset >= len(table):
            fail("invalid cmap offset")
        offsets.add(offset)
    result: set[int] = set()
    for offset in offsets:
        format_number = struct.unpack_from(">H", table, offset)[0]
        if format_number == 4:
            if offset + 14 > len(table):
                fail("invalid format 4 cmap")
            length = struct.unpack_from(">H", table, offset + 2)[0]
            segment_bytes = struct.unpack_from(">H", table, offset + 6)[0]
            if length < 16 or offset + length > len(table) or segment_bytes % 2:
                fail("invalid format 4 length")
            segments = segment_bytes // 2
            end_base = offset + 14
            start_base = end_base + 2 * segments + 2
            delta_base = start_base + 2 * segments
            range_base = delta_base + 2 * segments
            if range_base + 2 * segments > offset + length:
                fail("truncated format 4 cmap")
            for segment in range(segments):
                end = struct.unpack_from(">H", table, end_base + 2 * segment)[0]
                start = struct.unpack_from(">H", table, start_base + 2 * segment)[0]
                delta = struct.unpack_from(">H", table, delta_base + 2 * segment)[0]
                range_offset_position = range_base + 2 * segment
                range_offset = struct.unpack_from(">H", table, range_offset_position)[0]
                for codepoint in range(start, end + 1):
                    if codepoint == 0xFFFF:
                        continue
                    if range_offset == 0:
                        glyph = (codepoint + delta) & 0xFFFF
                    else:
                        glyph_position = range_offset_position + range_offset + 2 * (codepoint - start)
                        if glyph_position + 2 > offset + length:
                            fail("invalid format 4 glyph offset")
                        glyph = struct.unpack_from(">H", table, glyph_position)[0]
                        if glyph:
                            glyph = (glyph + delta) & 0xFFFF
                    if glyph:
                        result.add(codepoint)
        elif format_number == 12:
            if offset + 16 > len(table):
                fail("invalid format 12 cmap")
            length, groups = struct.unpack_from(">II", table, offset + 4)[0], struct.unpack_from(">I", table, offset + 12)[0]
            if length < 16 or offset + length > len(table) or 16 + 12 * groups > length:
                fail("invalid format 12 length")
            for group in range(groups):
                start, end, glyph = struct.unpack_from(">III", table, offset + 16 + 12 * group)
                if end < start or end - start > 0x10000:
                    fail("invalid format 12 group")
                for codepoint in range(start, end + 1):
                    if glyph + codepoint - start:
                        result.add(codepoint)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("font", type=Path)
    parser.add_argument("--public-dummy", action="store_true")
    args = parser.parse_args()
    data = args.font.read_bytes()
    if len(data) > 1024 * 1024:
        fail("font exceeds 1 MiB")
    directory = tables(data)
    for required in (b"CFF ", b"OS/2", b"cmap", b"head", b"hhea", b"hmtx", b"maxp", b"name"):
        if required not in directory:
            fail(f"missing {required.decode('ascii').strip()} table")
    if len(directory[b"OS/2"]) < 10 or struct.unpack_from(">H", directory[b"OS/2"], 8)[0] & 0x0002:
        fail("font embedding is restricted")
    codepoints = cmap_codepoints(directory[b"cmap"])
    if 0x201A not in codepoints:
        fail("U+201A is not mapped")
    visible = codepoints - {0x20, 0x00A0}
    if visible != {0x201A}:
        fail("only U+201A may be a visible mapped character")
    if args.public_dummy:
        generated = __import__("generate_dummy_signature_font").build_font()
        if data != generated:
            fail("tracked public font is not the reproducible dummy")
    print(f"Valid signature font: {args.font} ({len(data)} bytes, U+201A)")


if __name__ == "__main__":
    main()
