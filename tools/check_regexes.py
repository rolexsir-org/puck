#!/usr/bin/env python3
"""Extract every `RegExp(...)` literal in the Dart sources and check it.

Why this exists: a regex that is *nearly* right fails silently, and the failure
lands on a user. The specific bug it was written for is the one that shipped
into this branch and was caught by reading, not by a test:

    RegExp(r'^[\\s]*')      # a raw string: regex sees \\s -- backslash, or "s"

In a raw Dart string nothing is escaped, so writing `\\\\s` (two backslashes)
means the pattern contains `\\` -- an escaped backslash -- followed by a literal
`s`. The character class silently stops matching whitespace and starts matching
the letter s, and every caller that depended on it quietly changes behaviour.
There is no analyzer rule for this, and the pattern still compiles.

What it checks, per pattern:

  1. A **raw** string whose extracted pattern contains two adjacent backslash
     characters. In a raw string that is an escaped backslash followed by a
     literal, not a class shorthand -- almost always the mistake above. This one
     fails the run. (Proved by planting the bug in a scratch file: see the
     self-test note at the bottom of this docstring.)
  2. A **non-raw** string whose extracted pattern ends in an odd number of
     backslashes -- an unterminated escape. Fails the run.
  3. The pattern is compiled with Python's `re`, as an advisory. Dart-only
     syntax (`\\p{L}`, atomic groups, `(?<name>)`) shows up here as "not
     checkable"; anything else that fails to compile is worth a look.

Usage: python3 tools/check_regexes.py [root]     (exit 1 if anything failed)

Self-test, so the checker is not just a thing that prints "ok":

    mkdir -p /tmp/probe/lib
    printf "void f() { RegExp(r'^[\\\\s]*'); }\n" > /tmp/probe/lib/a.dart
    python3 tools/check_regexes.py /tmp/probe      # exits 1, names the line
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

# RegExp(  'a' 'b'  ), RegExp(r'a' r'b'), mixed raw and non-raw literal runs.
LITERAL = re.compile(r"""(['"])((?:[^\\]|\\.)*?)\1""", re.S)


def unquote(text: str, raw: bool) -> str:
    """The string value Dart would produce, as far as a regex cares."""
    if raw:
        # A raw string has no escapes, but it can contain an escaped quote.
        return text.replace("\\'", "'").replace('\\"', '"')
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "n":
                out.append("\n")
            elif nxt == "t":
                out.append("\t")
            elif nxt == "r":
                out.append("\r")
            elif nxt == "u" and i + 5 < len(text):
                out.append(chr(int(text[i + 2 : i + 6], 16)))
                i += 6
                continue
            else:
                out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def literal_run(source: str, start: int) -> tuple[str, int] | None:
    """Consume a run of adjacent string literals after `RegExp(`."""
    i = start
    parts: list[str] = []
    raw_flags: list[bool] = []
    while True:
        while i < len(source) and source[i] in " \t\r\n":
            i += 1
        raw = source.startswith("r'", i) or source.startswith('r"', i)
        j = i + 1 if raw else i
        match = LITERAL.match(source, j)
        if match is None:
            break
        parts.append(unquote(match.group(2), raw))
        raw_flags.append(raw)
        i = match.end()
    if not parts:
        return None
    return "".join(parts), i


def main() -> int:
    pattern_calls = 0
    failures: list[str] = []
    advisories: list[str] = []

    for path in sorted(
        p for p in ROOT.rglob("*.dart") if ".git" not in p.parts
    ):
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\bRegExp\(", source):
            parsed = literal_run(source, match.end())
            if parsed is None:
                continue  # RegExp(variable) -- nothing static to check
            pattern, _ = parsed
            line = source[: match.start()].count("\n") + 1
            where = f"{path.relative_to(ROOT)}:{line}"
            pattern_calls += 1

            if "\\\\" in pattern:
                failures.append(
                    f"{where}: the pattern contains a literal backslash "
                    f"(two backslash characters) -- in a raw Dart string "
                    f"'\\\\s' is backslash-then-s, not whitespace: {pattern!r}"
                )
            trailing = len(pattern) - len(pattern.rstrip(chr(92)))
            if trailing % 2 == 1:
                failures.append(f"{where}: odd trailing backslash: {pattern!r}")

            try:
                re.compile(pattern)
            except re.error as error:
                if re.search(r"\\[pP]\{", pattern) or "(?<" in pattern:
                    advisories.append(
                        f"{where}: uses syntax Python's re lacks "
                        f"({error}); not checkable here"
                    )
                else:
                    advisories.append(
                        f"{where}: Python's re rejects it ({error}): "
                        f"{pattern!r}"
                    )

    for note in advisories:
        print(f"note: {note}")
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    print("---")
    print(
        f"{pattern_calls} RegExp literals checked, "
        f"{len(failures)} suspicious, {len(advisories)} not checkable"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
