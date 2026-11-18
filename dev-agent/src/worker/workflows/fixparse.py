"""Extract a unified diff from an LLM proposal. Stdlib only, so it is unit-testable."""

import re

_FENCED_DIFF = re.compile(r"```diff\n(.*?)```", re.DOTALL)


def extract_diff(text: str) -> str | None:
    """Return a unified diff from the model output, or None if there is none."""
    if not text:
        return None
    match = _FENCED_DIFF.search(text)
    if match:
        diff = match.group(1).strip()
        return diff + "\n" if diff else None
    if "--- a/" in text:
        start = text.find("--- a/")
        diff = text[start:].strip()
        return diff + "\n" if diff else None
    return None
