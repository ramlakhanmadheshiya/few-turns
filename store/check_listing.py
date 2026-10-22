#!/usr/bin/env python3
"""Checks the Play listing text in store/listing.md against Play's limits and
wording rules (no "best", "#1", "free", "new", "download now")."""
import re, sys, pathlib

text = pathlib.Path(__file__).with_name("listing.md").read_text()


def section(title):
    m = re.search(r"## " + re.escape(title) + r"[^\n]*\n\n(.*?)(?=\n## |\Z)", text, re.S)
    return m.group(1).strip() if m else ""


ok = True
for title, limit in [("App name", 30), ("Short description", 80), ("Full description", 4000)]:
    body = section(title)
    n = len(body)
    flag = "OK" if 0 < n <= limit else "TOO LONG"
    ok &= flag == "OK"
    print(f"{title}: {n}/{limit} {flag}")
banned = ["best", "#1", "number one", "free", "new", "download now", "top"]
for title in ["App name", "Short description"]:
    body = section(title).lower()
    for w in banned:
        if re.search(r"\b" + re.escape(w) + r"\b", body):
            ok = False
            print(f"{title}: avoid the word '{w}'")
sys.exit(0 if ok else 1)
