#!/usr/bin/env python3
"""Read-only scan for node titles replaced by the former AX diagnostic string."""

from __future__ import annotations

import re
import zipfile
from pathlib import Path


PATTERN = re.compile(rb'(?<![A-Za-z0-9])mode=(edit|view);fill=#[0-9A-F]{6};w=[0-9.]+;h=[0-9.]+(?=["\\s,}]|$)')
HOME = Path.home()
ROOTS = [
    HOME / "Library/Containers/net.timhuang.floretta/Data/Documents",
    HOME / "Library/Containers/app.floretta.macos/Data/Documents",
    HOME / "Library/Application Support/Floretta/Autosave",
    HOME / "Library/Mobile Documents/iCloud~net~timhuang~floretta/Documents",
    HOME / "Library/Autosave Information",
]


def count_matches(data: bytes) -> int:
    """Count exact serialized node-title values, including values in JSON strings."""
    return len(PATTERN.findall(data))


def scan_file(path: Path) -> int:
    try:
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                return sum(count_matches(archive.read(name)) for name in archive.namelist() if not name.endswith("/"))
        return count_matches(path.read_bytes())
    except (OSError, zipfile.BadZipFile):
        return 0


def main() -> None:
    print("READ-ONLY Floretta node-text corruption scan")
    total_files = 0
    total_matches = 0
    for root in ROOTS:
        if not root.exists():
            print(f"{root}: unavailable (not present)")
            continue
        files = [path for path in root.rglob("*") if path.is_file()]
        root_matches = 0
        for path in files:
            matches = scan_file(path)
            if matches:
                print(f"{path}: {matches}")
                root_matches += matches
        print(f"{root}: {root_matches} matching nodes across {len(files)} files")
        total_files += len(files)
        total_matches += root_matches
    print(f"TOTAL: {total_matches} matching nodes across {total_files} files")
    print("No files were modified.")


if __name__ == "__main__":
    main()
