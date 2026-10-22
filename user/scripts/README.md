# scripts

Small standalone scripts that don't belong to a larger project.

## crc32

Checksum tool for binary files.

### Purpose

Verify or stamp CRC-32 checksums on binary images.

### What it does

- Computes a CRC-32/MPEG-2 checksum over a whole file or from a chosen offset
- Appends the checksum to the file
- Writes the checksum to a separate file
- Handles files that already end in a checksum

### What it does not do

- Support other CRC variants

### Requirements

- Python 3, with no third-party packages
