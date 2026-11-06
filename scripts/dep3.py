#!/usr/bin/python3 -I
"""Convert an overlay patch (git format-patch or plain diff) to a DEP-3 patch."""

import argparse
import email.utils
import re
import sys


def split_patch(text):
    """Split a patch into its description part and the diff."""
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith("diff ") or line.startswith("Index: "):
            return lines[:i], lines[i:]
        if (line.startswith("--- ") and i + 1 < len(lines)
                and lines[i + 1].startswith("+++ ")):
            return lines[:i], lines[i:]
    sys.exit("dep3.py: no diff found")


def strip_signature(diff):
    """Drop the trailing '-- \\n<git version>' added by git format-patch."""
    for i in range(len(diff) - 1, -1, -1):
        if diff[i] == "-- \n":
            if all(re.match(r"\d[\w.]*\n?$", line) or not line.strip() for line in diff[i + 1:]):
                return diff[:i]
            break
    return diff


def parse_header(head):
    """Return (author, date, subject, body lines) of a git format-patch header."""
    author = date = subject = None
    body = []
    i = 0
    if head and re.match(r"From [0-9a-f]{40} ", head[0]):
        i = 1
    while i < len(head) and head[i].strip():
        line = head[i].rstrip("\n")
        if line.startswith("From: "):
            author = line[6:].strip()
        elif line.startswith("Date: "):
            date = line[6:].strip()
        elif line.startswith("Subject: "):
            subject = line[9:].strip()
            while i + 1 < len(head) and head[i + 1].startswith(" "):
                i += 1
                subject += " " + head[i].strip()
        i += 1
    for line in head[i:]:
        line = line.rstrip("\n")
        if line == "---":
            break
        if line.startswith("Signed-off-by:"):
            continue
        body.append(line)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    if subject:
        subject = re.sub(r"^\[PATCH[^]]*\]\s*", "", subject)
    return author, date, subject, body


def is_diffstat(line):
    return bool(re.match(r"\s*\S.*\|\s+(\d+ ?[+-]*|Bin .*)$", line)
                or re.match(r"\s*\d+ files? changed", line)
                or re.match(r"\s*(create|delete) mode \d+ ", line))


def description_from_name(name):
    stem = re.sub(r"\.(patch|diff)$", "", name)
    stem = re.sub(r"^(\d+-)?(CUSTOM-|REVERT-)?(\d+-)?", "", stem)
    words = stem.replace("_", " ").replace("-", " ").strip()
    return words[:1].upper() + words[1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patch")
    parser.add_argument("--name", required=True, help="patch file name")
    parser.add_argument("--origin", required=True, help="Origin URL of the patch")
    parser.add_argument("--author", required=True, help="author when the patch has none")
    parser.add_argument("--email", required=True, help="email address added to an author without one")
    parser.add_argument("--description", help="description of a patch without a header")
    args = parser.parse_args()

    with open(args.patch, encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    head, diff = split_patch(text)
    author, date, subject, body = parse_header(head)

    if not subject:
        subject = args.description or description_from_name(args.name)
        body = [] if args.description else [
            line.rstrip("\n") for line in head
            if line.strip() and line.strip() != "---" and not is_diffstat(line)]
    if not author:
        author = args.author
    if "<" not in author:
        author = f"{author} <{args.email}>"

    out = [f"Description: {subject}\n"]
    if body:
        out.append(" .\n")
        out += [f" {line}\n" if line.strip() else " .\n" for line in body]
    out.append(f"Author: {author}\n")
    out.append(f"Origin: vendor, {args.origin}\n")
    out.append("Forwarded: not-needed\n")
    if date:
        parsed = email.utils.parsedate_to_datetime(date)
        out.append(f"Last-Update: {parsed:%Y-%m-%d}\n")
    out.append("---\n")
    out += strip_signature(diff)
    sys.stdout.buffer.write("".join(out).encode("utf-8", "surrogateescape"))


if __name__ == "__main__":
    main()
