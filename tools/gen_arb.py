#!/usr/bin/env python3
"""Regenerate lib/l10n/*.arb from the Dart string maps.

The strings live in Dart (`lib/src/l10n/puck_strings.dart` and
`strings_<code>.dart`) because that is what the app reads at runtime; the ARB
files exist so a translator -- or a translation service -- has a file to work
with, and so the key set is machine-checkable. `flutter gen-l10n` is
deliberately not used: it would generate a second, parallel set of accessors
next to the typed ones the app already has (see the class doc in
`puck_strings.dart`).

So the two must be kept in step by hand or by this script. Run it after editing
either map:

    python3 tools/gen_arb.py

`test/core/strings_test.dart` fails if the files and the maps disagree, in
either direction, so a missed run is caught by `flutter test` rather than by a
user seeing "Nothing urgent." next to a Spanish card.

The Dart is parsed, not grepped: values are commonly written as several
adjacent string literals across lines, and a line-based `sed`-style extractor
silently truncates those to the first literal (which is exactly how the ARB
files were first generated -- one string lost half its sentence). Only the
standard library is used, so this runs wherever Python 3 and Flutter do.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Iterator

ROOT = pathlib.Path(__file__).resolve().parent.parent
L10N = ROOT / "lib" / "l10n"
STRINGS = ROOT / "lib" / "src" / "l10n"

ENGLISH_DECL = re.compile(r"static const Map<String, String> _en\b")
TRANSLATION_DECL = re.compile(r"const Map<String, String> strings[A-Za-z]+\b")


def _skip_line_comment(text: str, i: int) -> int:
    end = text.find("\n", i)
    return len(text) if end < 0 else end + 1


def _literal(text: str, i: int) -> tuple[str, int]:
    """Read one single-quoted Dart literal starting at `text[i] == "'"`."""
    assert text[i] == "'"
    i += 1
    out: list[str] = []
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            nxt = text[i + 1] if i + 1 < len(text) else ""
            out.append({"n": "\n", "t": "\t", "'": "'", '"': '"'}.get(nxt, nxt))
            i += 2
            continue
        if ch == "'":
            return "".join(out), i + 1
        out.append(ch)
        i += 1
    raise ValueError("unterminated string literal")


def _map_body(text: str, start: int) -> str:
    """Return the text between the outer braces of the map at/after `start`."""
    i = text.index("{", start)
    depth = 0
    j = i
    while j < len(text):
        ch = text[j]
        if ch == "'":
            _, j = _literal(text, j)
            continue
        if ch == "/" and text.startswith("//", j):
            j = _skip_line_comment(text, j)
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1 : j]
        j += 1
    raise ValueError("unbalanced braces in map body")


def entries(body: str) -> Iterator[tuple[str, str]]:
    """Yield (key, value) pairs from a `'key': 'value' 'value',` map body."""
    i = 0
    n = len(body)
    while i < n:
        while i < n and body[i] in " \t\r\n,":
            i += 1
        if i >= n:
            return
        if body[i] == "/" and body.startswith("//", i):
            i = _skip_line_comment(body, i)
            continue
        if body[i] != "'":
            # Something that is not a key: a doc comment or a stray token.
            # Step past it rather than guessing.
            i = _skip_line_comment(body, i)
            continue
        key, i = _literal(body, i)
        while i < n and body[i] in " \t":
            i += 1
        if i < n and body[i] == ":":
            i += 1
        parts: list[str] = []
        while True:
            probe = i
            while probe < n and body[probe] in " \t\r\n":
                probe += 1
            if probe < n and body[probe] == "'":
                lit, i = _literal(body, probe)
                parts.append(lit)
            else:
                break
        if not parts:
            # A key whose value is not a literal (e.g. 'en': _en). Not a
            # translatable string; skip.
            continue
        yield key, "".join(parts)


def extract(path: pathlib.Path, decl: re.Pattern[str]) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = decl.search(text)
    if match is None:
        raise ValueError(f"no map declaration in {path}")
    return dict(entries(_map_body(text, match.start())))


def write(locale: str, strings: dict[str, str]) -> None:
    L10N.mkdir(parents=True, exist_ok=True)
    out: dict[str, str] = {"@@locale": locale}
    out.update(strings)
    target = L10N / f"app_{locale}.arb"
    target.write_text(
        json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"{target.relative_to(ROOT)}: {len(strings)} keys")


def main() -> int:
    en = extract(STRINGS / "puck_strings.dart", ENGLISH_DECL)
    if not en:
        print("error: no English strings found", file=sys.stderr)
        return 1
    write("en", en)

    translations = sorted(STRINGS.glob("strings_*.dart"))
    if not translations:
        print("error: no translation maps found", file=sys.stderr)
        return 1

    failed = False
    for path in translations:
        locale = path.stem.split("_", 1)[1]
        table = extract(path, TRANSLATION_DECL)
        missing = sorted(set(en) - set(table))
        extra = sorted(set(table) - set(en))
        if missing or extra:
            # Refusing to write is the point: a half-translated file that
            # silently ships English gaps is worse than a build error.
            print(f"{path.name}: missing {missing} extra {extra}", file=sys.stderr)
            failed = True
            continue
        write(locale, table)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
