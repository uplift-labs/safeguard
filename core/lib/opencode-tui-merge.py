#!/usr/bin/env python3
"""Merge Safeguard OpenCode TUI plugin config.

Usage:
    python3 opencode-tui-merge.py <target_tui.json> <plugin_spec>
"""
import json
import re
import sys
from pathlib import Path


def strip_jsonc(text):
    out = []
    i = 0
    in_string = False
    quote = ""
    escape = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_string:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            quote = ch
            out.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            i += 2
            while i < len(text) and text[i] not in "\r\n":
                i += 1
            continue

        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < len(text) and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue

        out.append(ch)
        i += 1

    return re.sub(r",\s*([}\]])", r"\1", "".join(out))


def plugin_key(item):
    if isinstance(item, str):
        return item
    if isinstance(item, list) and item and isinstance(item[0], str):
        return item[0]
    return None


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <target_tui.json> <plugin_spec>", file=sys.stderr)
        return 1

    target_path = Path(sys.argv[1])
    plugin_spec = sys.argv[2]

    if target_path.exists():
        text = target_path.read_text(encoding="utf-8")
        data = json.loads(strip_jsonc(text or "{}"))
        if not isinstance(data, dict):
            data = {}
    else:
        data = {"$schema": "https://opencode.ai/tui.json"}

    plugins = data.get("plugin")
    if not isinstance(plugins, list):
        plugins = []

    if plugin_spec not in [plugin_key(item) for item in plugins]:
        plugins.append(plugin_spec)
    data["plugin"] = plugins

    if "$schema" not in data:
        data = {"$schema": "https://opencode.ai/tui.json", **data}

    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
