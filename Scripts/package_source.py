# SPDX-License-Identifier: MPL-2.0
"""Create a reviewable source ZIP without Git history or local signing files."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import sys
from audit_source import ROOT, audit, source_files

result = audit()
if result["findings"]:
    raise SystemExit("Source audit failed. Resolve findings before packaging.")
output = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "DuaLink-iOS-MPL-2.0-Review.zip"
if output.exists():
    raise SystemExit("Output already exists; choose a new path to preserve the earlier review package.")
with ZipFile(output, "w", ZIP_DEFLATED, compresslevel=9) as archive:
    for path in source_files():
        if path.resolve() == output.resolve() or "__pycache__" in path.parts:
            continue
        archive.write(path, "DuaLinkSource/" + path.relative_to(ROOT).as_posix())
print(output.name)
