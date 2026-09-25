#!/usr/bin/env python3
"""Compare every downloaded export object's MD5/size against GCS and save SHA256."""

import base64
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def gsutil(*args: str) -> str:
    return subprocess.check_output(["gsutil", *args], text=True)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: verify_firestore_export.py gs://prefix local-dir output.json")
    prefix, local_dir, output = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    if not prefix.startswith("gs://") or not local_dir.is_dir():
        raise SystemExit("Invalid export prefix or local directory")
    remote = sorted(line for line in gsutil("ls", "-r", prefix + "/**").splitlines()
                    if line.startswith(prefix + "/") and not line.endswith("/"))
    relative = [name[len(prefix) + 1:] for name in remote]
    local = sorted(str(path.relative_to(local_dir)) for path in local_dir.rglob("*") if path.is_file())
    if sorted(relative) != local:
        raise SystemExit("Remote/local file list mismatch")
    expected_metadata = prefix.rsplit("/", 1)[-1] + ".overall_export_metadata"
    if expected_metadata not in local:
        raise SystemExit("Overall export metadata missing or renamed")
    entries = []
    for name in remote:
        rel = name[len(prefix) + 1:]
        data = (local_dir / rel).read_bytes()
        info = gsutil("stat", name)
        md5 = re.search(r"Hash \(md5\):\s+(\S+)", info)
        size = re.search(r"Content-Length:\s+(\d+)", info)
        if not md5 or not size or base64.b64encode(hashlib.md5(data).digest()).decode() != md5.group(1) or len(data) != int(size.group(1)):
            raise SystemExit(f"Checksum/size mismatch: {rel}")
        entries.append({"path": rel, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"prefix": prefix, "files": entries}, indent=2) + "\n")
    print(f"Verified {len(entries)} objects; manifest {output}")


if __name__ == "__main__":
    main()
