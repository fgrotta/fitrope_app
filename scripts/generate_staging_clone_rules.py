#!/usr/bin/env python3
"""Generate fail-closed Firestore rules for the five staging clone accounts."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "firestore.rules"
TARGET = ROOT / ".context" / "staging-clone.rules"
MATCH = "return request.auth != null;"
ALLOWED_UIDS = (
    "dev_admin",
    "dev_trainer",
    "dev_member_open_2x",
    "dev_member_open_unlimited",
    "dev_member_pt_entries",
)


def main() -> None:
    source = SOURCE.read_text()
    if source.count(MATCH) != 1:
        raise SystemExit("isSignedIn predicate changed; clone rules not generated")
    replacement = (
        "return request.auth != null && request.auth.uid in ["
        + ", ".join(f"'{uid}'" for uid in ALLOWED_UIDS)
        + "];"
    )
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(
        "// Generated from firestore.rules by scripts/generate_staging_clone_rules.py\n"
        + source.replace(MATCH, replacement)
    )
    print(TARGET.relative_to(ROOT))


if __name__ == "__main__":
    main()
