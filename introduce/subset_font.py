#!/usr/bin/env python3
"""Subset Nebulove into a cacheable WOFF2 for introduce/index.html.

Optional maintenance/CI tool, not a runtime build requirement.
Run: pip install fonttools brotli && python introduce/subset_font.py
Use --force to refresh the upstream font, or NEBULOVE_FONT=/path/to/font.ttf offline.
"""
import hashlib
from html.parser import HTMLParser
import io
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
FONT_URL = "https://raw.githubusercontent.com/lingyicute/Nebulove/main/Nebulove.ttf"
HTML_PATH = ROOT / "introduce/index.html"
CACHE_PATH = ROOT / "introduce/.font-subset-cache.json"
OUTPUT = ROOT / "introduce/fonts/nebulove-subset.woff2"
FAMILY = "Nebulove"
PUNCT = "：，。！？；“”‘’（）【】—…·《》×＝÷＋－→❯「」\u200d\ufe0e\ufe0f"
PRELOAD = (
    '<link rel="preload" href="fonts/nebulove-subset.woff2" '
    'as="font" type="font/woff2" crossorigin>\n'
)


class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ignored = 0
        self.chars = set()

    def handle_starttag(self, tag, attrs):
        if tag in {"head", "script", "style"}:
            self.ignored += 1
        if not self.ignored:
            for name, value in attrs:
                if name in {"alt", "title", "aria-label", "placeholder"} and value:
                    self.chars.update(value)

    def handle_endtag(self, tag):
        if tag in {"head", "script", "style"}:
            self.ignored = max(0, self.ignored - 1)

    def handle_data(self, text):
        if not self.ignored:
            self.chars.update(text)


def collect_chars(html):
    parser = VisibleText()
    parser.feed(html)
    chars = parser.chars
    # Avoid subsetting Chinese code comments, SVG paths or base64 blobs as visible text.
    for style in re.findall(r"<style\b[^>]*>(.*?)</style>", html, flags=re.S | re.I):
        css = re.sub(r"/\*.*?\*/", "", style, flags=re.S)
        for content in re.findall(r"content:\s*['\"]([^'\"]*)['\"]", css):
            chars.update(content)
    # Terminal demo, snackbar and architecture note are injected from JS strings.
    for script in re.findall(r"<script\b[^>]*>(.*?)</script>", html, flags=re.S | re.I):
        code = re.sub(r"/\*.*?\*/", "", script, flags=re.S)
        code = re.sub(r"//.*?$", "", code, flags=re.M)
        for match in re.finditer(r"(['\"`])((?:\\.|(?!\1).)*)\1", code):
            chars.update(match.group(2))
    chars.update(chr(c) for c in range(32, 127))  # Includes years / English UI.
    chars.update(PUNCT)
    return chars


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def subset(font, chars):
    from fontTools.subset import Options, Subsetter

    subsetter = Subsetter(options=Options())
    subsetter.populate(unicodes=sorted(ord(c) for c in chars))
    subsetter.subset(font)
    font.flavor = "woff2"
    font.recalcTimestamp = False
    output = io.BytesIO()
    font.save(output)
    return output.getvalue()


def replace_face(html, family, filename):
    for match in re.finditer(r"@font-face\s*\{[^{}]*\}", html):
        if re.search(r"font-family:\s*['\"]" + re.escape(family) + r"['\"]\s*;", match[0]):
            face = (
                "@font-face {\n"
                f"  font-family: '{family}';\n"
                f"  src: url('fonts/{filename}') format('woff2');\n"
                "  font-weight: 100 900;\n"
                "  font-display: swap;\n"
                "}"
            )
            return html[: match.start()] + face + html[match.end() :]
    raise ValueError(f"Missing font-face: {family}")


def ensure_preload(html):
    # Do not treat an unrelated preload link as the font preload.
    font_preload = re.compile(
        r"<link\b(?=[^>]*\brel\s*=\s*['\"]preload['\"])"
        r"(?=[^>]*\bhref\s*=\s*['\"]fonts/nebulove-subset\.woff2['\"])[^>]*>",
        flags=re.I,
    )
    if font_preload.search(html):
        return html
    style = html.find("<style>")
    if style < 0:
        raise ValueError("Missing <style> to attach font preload")
    return html[:style] + PRELOAD + html[style:]


def main():
    from fontTools.ttLib import TTFont

    html = HTML_PATH.read_text(encoding="utf-8")
    chars = collect_chars(html)
    local_font = os.environ.get("NEBULOVE_FONT")
    source_key = digest(Path(local_font)) if local_font else FONT_URL
    source_label = str(Path(local_font).resolve()) if local_font else FONT_URL
    fingerprint = hashlib.sha256((
        source_key + digest(Path(__file__))
        + json.dumps(sorted(ord(c) for c in chars))
    ).encode()).hexdigest()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if "--force" not in sys.argv and CACHE_PATH.exists() and OUTPUT.exists():
        cached = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        if (
            cached.get("fingerprint") == fingerprint
            and OUTPUT.name in html
            and cached.get("outputs", {}).get(OUTPUT.name) == digest(OUTPUT)
        ):
            print("Visible charset unchanged; WOFF2 subset is current.")
            return

    if local_font:
        nebulove = TTFont(local_font)
    else:
        print("Downloading Nebulove source font...")
        with urllib.request.urlopen(FONT_URL, timeout=90) as response:
            nebulove = TTFont(io.BytesIO(response.read()))
    woff2 = subset(nebulove, chars)

    new_html = replace_face(html, FAMILY, OUTPUT.name)
    new_html = ensure_preload(new_html)
    assert new_html.count("@font-face") == html.count("@font-face")
    OUTPUT.write_bytes(woff2)
    HTML_PATH.write_text(new_html, encoding="utf-8")
    CACHE_PATH.write_text(json.dumps({
        "fingerprint": fingerprint,
        "source": source_label,
        "charset_count": len(chars),
        "outputs": {OUTPUT.name: digest(OUTPUT)},
    }, indent=2) + "\n", encoding="utf-8")
    print(f"{OUTPUT.name}: {len(woff2):,} bytes ({len(chars)} glyphs requested)")
    print("Updated introduce/index.html to the local subset; no remote font URL.")


if __name__ == "__main__":
    main()
