"""Add a minimal ComicInfo.xml to comic archives.

Komga does not read book numbers from file names: a CBZ without a
ComicInfo.xml is numbered by its position inside the series folder. The
series name is taken from the parent folder, the number from the last run
of digits in the file name. Archives that already contain a ComicInfo.xml
are left untouched, so repeated runs are safe.
"""

import re
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ENTRY = "ComicInfo.xml"


def comic_info(series: str, number: str) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<ComicInfo>\n"
        f"  <Series>{escape(series)}</Series>\n"
        f"  <Number>{escape(number)}</Number>\n"
        "</ComicInfo>\n"
    )


def number_of(name: str) -> str | None:
    numbers = re.findall(r"\d+", name)
    return numbers[-1] if numbers else None


def update(path: Path) -> bool:
    try:
        with zipfile.ZipFile(path) as archive:
            if ENTRY in archive.namelist():
                return False
    except zipfile.BadZipFile:
        print(f"{path}: not a zip archive, skipping")
        return False

    number = number_of(path.stem)
    if number is None:
        print(f"{path}: no number in file name, skipping")
        return False

    with zipfile.ZipFile(path, "a") as archive:
        archive.writestr(ENTRY, comic_info(path.parent.name, number))
    print(
        f"{path}: added {ENTRY} "
        f"(series={path.parent.name}, number={number})"
    )
    return True


def main(roots: list[str]) -> int:
    updated = 0
    for root in roots:
        directory = Path(root)
        if not directory.is_dir():
            print(f"{root}: not a directory, skipping")
            continue
        for path in sorted(directory.rglob("*.cbz")):
            updated += update(path)
    print(f"{updated} archive(s) updated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
