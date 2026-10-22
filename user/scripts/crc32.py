# ==============================================================================
# Filename:         crc32.py
# Description:      Compute and optionally append or patch a CRC-32 checksum for a
#                   binary file.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-10-21
# License:          AGPL-3.0
# ==============================================================================

"""Compute and optionally append or patch a CRC-32 checksum for a binary file."""

import argparse
import os
import sys
import zlib
from typing import Optional


# CRC-CCITT-32
def crc32mod(data: bytes) -> int:
    return (zlib.crc32(data, 0) & 0xFFFFFFFF) ^ 0xFFFFFFFF


def read_file_crc32(
    filepath: str,
    start_offset: int = 0,
    end_offset: int = 4,
) -> int:
    """Compute the CRC-32 of a file, optionally comparing a trailing stored value.

    Args:
        filepath: Path to the binary file.
        start_offset: Bytes to skip from the start before computing.
        end_offset: When > 0, treats the last 4 bytes as the stored CRC and
                    computes over all preceding bytes.  When 0, computes over
                    the entire (post-skip) payload.

    Returns:
        The computed CRC-32 value.

    Raises:
        ValueError: If end_offset < 0 or the file is too small to hold a CRC.
    """
    if end_offset < 0:
        raise ValueError("end_offset must be >= 0")

    with open(filepath, "rb") as f:
        raw = f.read()

    data = raw[start_offset:]

    if end_offset > 0:
        if len(data) < 4:
            raise ValueError("File is too small to contain a CRC-32 value.")

        payload = data[:-4]
        computed = crc32mod(payload)
        stored = int.from_bytes(data[-4:], byteorder="little")

        print(
            f"Size of file:            {len(data)}\n"
            f"Size without CRC:        {len(payload)}\n"
            f"Stored CRC32 (last 4):   {stored}, 0x{stored:08X}\n"
            f"Computed CRC32:          {computed}, 0x{computed:08X}\n"
            f"Match:                   {stored == computed}"
        )
        return computed

    computed = crc32mod(data)
    print(f"Computed CRC32 of whole file: {computed}, 0x{computed:08X}")
    return computed


def write_file_crc32(
    filepath: str,
    crc32: int,
    endian: str = "little",
    write_offset: Optional[int] = None,
) -> None:
    """Write a 4-byte CRC-32 value to a file.

    When write_offset is None the value is appended to the end of the file.
    When write_offset is specified the value is written in-place at that byte
    position (the file must already exist).

    Args:
        filepath: Target file path.
        crc32: CRC-32 value to write.
        endian: Byte order – "little" or "big".
        write_offset: Byte offset at which to write; None means append.
    """
    crc_bytes = crc32.to_bytes(4, byteorder=endian)

    # Append mode always writes at EOF regardless of seek; use r+b for in-place.
    mode = "r+b" if write_offset is not None else "ab"

    with open(filepath, mode) as f:
        if write_offset is not None:
            f.seek(write_offset, os.SEEK_SET)
        offset = f.tell()
        f.write(crc_bytes)

    print(
        f"Wrote {crc32} (0x{crc32:08X}) [{crc_bytes.hex(' ')}] "
        f"at offset {offset} of '{filepath}'"
    )


def main(args: argparse.Namespace) -> None:
    """Orchestrate CRC computation and output from validated CLI arguments."""
    try:
        start_offset = args.start_offset or 0
        end_offset = 0 if args.whole_file else 4

        computed = read_file_crc32(args.filepath, start_offset, end_offset)

        if args.catcrc and args.outfile is None:
            write_file_crc32(args.filepath, computed)

        if args.outfile is not None:
            write_file_crc32(args.outfile, computed, write_offset=0)

    except FileNotFoundError:
        print(f"Error: File '{args.filepath}' not found.", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"Error: Permission denied for '{args.filepath}'.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=(
            "Compute a CRC-32/MPEG-2 checksum for a binary file and "
            "optionally append or patch the result."
        )
    )
    parser.add_argument("filepath", help="Path to the input file")
    parser.add_argument(
        "-w", "--whole-file",
        action="store_true",
        help="Compute CRC over the entire file (including any trailing CRC bytes)",
    )
    parser.add_argument(
        "-s", "--start-offset",
        type=lambda x: int(x, 0),
        metavar="OFFSET",
        help="Skip OFFSET bytes from the start before computing (hex or decimal)",
    )
    parser.add_argument(
        "-c", "--catcrc",
        action="store_true",
        help="Append the computed CRC-32 to the input file",
    )
    parser.add_argument(
        "-o", "--outfile",
        metavar="FILE",
        help="Write the computed CRC-32 to FILE at offset 0",
    )

    args = parser.parse_args()

    # catcrc always operates on the full file, not the payload-minus-CRC view
    if args.catcrc:
        args.whole_file = True

    main(args)