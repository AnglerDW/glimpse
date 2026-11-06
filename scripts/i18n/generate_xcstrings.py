#!/usr/bin/env python3
"""Generate the String Catalogs (.xcstrings) from scripts/i18n/strings.json.

    scripts/i18n/generate_xcstrings.py          # write the catalogs
    scripts/i18n/generate_xcstrings.py --check  # verify the catalogs on disk match the table, write nothing

The table is the source of truth (see its _readme). The script refuses to write when:
- an entry lacks a language, or a value is empty;
- the placeholders of a value are not exactly the entry's declared `placeholders`, in that order
  (only %@, %lld and %d are allowed; nothing is positional, so the order must be the source's);
- a French value has a plain space inside « » or before : ; ! ? (Apple's French uses U+00A0 before : and
  inside « », and U+202F before ; ! ?);
- a `String(localized:)` key used in the Swift sources has no entry, or its interpolations do not match the
  entry's placeholders (types come from the interpolated expression: see PLACEHOLDER_BY_EXPRESSION).
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TABLE = Path(__file__).resolve().parent / "strings.json"
ALLOWED_PLACEHOLDERS = ("%@", "%lld", "%d")
ANY_PERCENT = re.compile(r"%(?:\d+\$)?(?:lld|ld|llu|lu)?[A-Za-z@]?")  # a bare % is reported too
SOURCE_DIRS = {"app": ROOT / "App/Sources", "core": ROOT / "Core/Sources"}
# `String(localized: "key"` or `String(localized: "key", defaultValue: "text"`; Swift escapes allowed.
LOCALIZED_CALL = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"(?:,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)")?')
INTERPOLATION = re.compile(r"\\\(((?:[^()]|\([^()]*\))*)\)")
# What `String(localized:)` turns an interpolation into, by the interpolated expression. Strings become %@;
# the few non-String values are listed by the exact expression used in the code. Anything else is an error,
# so a new Int interpolation cannot silently end up declared as %@.
PLACEHOLDER_BY_EXPRESSION = {
    "count": "%lld",   # Int: StatusItemController 「关闭所有贴图 (N)」
    "status": "%d",    # OSStatus (Int32): SettingsModel registration failure
}
STRING_EXPRESSIONS = re.compile(r"^(?:[\w.$]+|\$0\.displayString|combo\.displayString|model\.version)$")
# French typography: a plain space must not sit inside « » or before the two-part punctuation marks.
FRENCH_BAD_SPACES = re.compile(r"« | »| :| ;| !| \?")  # U+0020 only; NBSP / NNBSP are other characters
NBSP, NNBSP = " ", " "


def placeholders(text: str) -> list[str]:
    found = [m.group(0) for m in ANY_PERCENT.finditer(text)]
    bad = [p for p in found if p not in ALLOWED_PLACEHOLDERS]
    if bad:
        raise SystemExit(f"{text!r}: only {ALLOWED_PLACEHOLDERS} are allowed, found {bad}")
    return found


def check_french(key: str, value: str) -> None:
    # The regex sees U+0020 only; NBSP and NNBSP are different characters and pass.
    if FRENCH_BAD_SPACES.search(value):
        raise SystemExit(f"{key!r}: French needs a non-breaking space inside « » and before : ; ! ? — {value!r}")
    for mark in ";!?":
        if f"{NBSP}{mark}" in value:
            raise SystemExit(f"{key!r}: French uses the narrow no-break space (U+202F) before {mark!r} — {value!r}")
    if f"{NNBSP}:" in value or f"«{NNBSP}" in value or f"{NNBSP}»" in value:
        raise SystemExit(f"{key!r}: French uses U+00A0 (not U+202F) before : and inside « » — {value!r}")


def catalog_for(table: dict, section: dict) -> dict:
    source = table["sourceLanguage"]
    languages = [source] + table["languages"]
    strings = {}
    for entry in section["strings"]:
        key = entry["key"]
        if key in strings:
            raise SystemExit(f"duplicate key: {key}")
        source_value = entry.get(source, key)
        declared = entry.get("placeholders", [])
        if placeholders(source_value) != declared:
            raise SystemExit(f"{key!r}: source has placeholders {placeholders(source_value)}, declared {declared}")
        localizations = {}
        for language in languages:
            value = entry.get(language, key if language == source else None)
            if not isinstance(value, str) or not value.strip():
                raise SystemExit(f"{key!r}: missing or empty {language}")
            if placeholders(value) != declared:
                raise SystemExit(f"{key!r}: placeholders in {language} ({value!r}) are not {declared} in that order")
            if language == "fr":
                check_french(key, value)
            localizations[language] = {"stringUnit": {"state": "translated", "value": value}}
        strings[key] = {
            "comment": entry["comment"],
            "extractionState": "manual",
            "localizations": localizations,
        }
    return {"sourceLanguage": source, "strings": strings, "version": "1.0"}


def render(catalog: dict) -> str:
    # Xcode's own formatting: sorted keys, two-space indent, a space before each colon.
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")) + "\n"


def swift_keys(directory: Path) -> dict[str, list[str]]:
    """Keys as `String(localized:)` produces them → the placeholders its interpolations become."""
    keys: dict[str, list[str]] = {}
    for path in sorted(directory.rglob("*.swift")):
        for literal, _default in LOCALIZED_CALL.findall(path.read_text()):
            found: list[str] = []

            def placeholder(match: re.Match) -> str:
                expression = match.group(1).strip()
                if expression in PLACEHOLDER_BY_EXPRESSION:
                    found.append(PLACEHOLDER_BY_EXPRESSION[expression])
                elif STRING_EXPRESSIONS.match(expression):
                    found.append("%@")
                else:
                    raise SystemExit(f"{path.relative_to(ROOT)}: cannot tell the type of \\({expression}) in {literal!r}; "
                                     "add it to PLACEHOLDER_BY_EXPRESSION")
                return found[-1]

            key = INTERPOLATION.sub(placeholder, literal).replace('\\"', '"')
            if key in keys and keys[key] != found:
                raise SystemExit(f"{key!r}: used with different interpolation types")
            keys[key] = found
    return keys


def check_sources(name: str, catalog: dict, table_entries: dict[str, list[str]]) -> None:
    used = swift_keys(SOURCE_DIRS[name])
    missing = sorted(k for k in used if k not in catalog["strings"])
    if missing:
        raise SystemExit(f"{name}: keys used in code but missing from the table:\n  " + "\n  ".join(missing))
    unused = sorted(k for k in catalog["strings"] if k not in used)
    if unused:
        raise SystemExit(f"{name}: keys in the table that no `String(localized:)` uses:\n  " + "\n  ".join(unused))
    for key, found in used.items():
        if found != table_entries[key]:
            raise SystemExit(f"{name}: {key!r} interpolates {found} in code but declares {table_entries[key]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify only; exit 1 when a catalog is out of date")
    args = parser.parse_args()

    table = json.loads(TABLE.read_text())
    stale = []
    for name, section in table["catalogs"].items():
        catalog = catalog_for(table, section)
        if name in SOURCE_DIRS:
            check_sources(name, catalog, {e["key"]: e.get("placeholders", []) for e in section["strings"]})
        output = ROOT / section["output"]
        text = render(catalog)
        summary = f"{output.relative_to(ROOT)} ({len(catalog['strings'])} keys × {1 + len(table['languages'])} languages)"
        if args.check:
            if not output.exists() or output.read_text() != text:
                stale.append(str(output.relative_to(ROOT)))
            else:
                print(f"ok  {summary}")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(text)
            print(f"wrote {summary}")
    if stale:
        print("out of date (run scripts/i18n/generate_xcstrings.py):\n  " + "\n  ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
