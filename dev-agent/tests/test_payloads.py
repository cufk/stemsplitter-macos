import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from worker.workflows.fixparse import extract_diff
from worker.workflows.payloads import is_self_push, parse_event


class ParseEventTests(unittest.TestCase):
    def test_push_event(self):
        event = {
            "ref": "refs/heads/vibe/stemsplitter-1c69f9",
            "after": "abc123",
            "repository": {"full_name": "cufk/stemsplitter-macos"},
        }
        repo, branch, sha = parse_event(event)
        self.assertEqual(repo, "cufk/stemsplitter-macos")
        self.assertEqual(branch, "vibe/stemsplitter-1c69f9")
        self.assertEqual(sha, "abc123")

    def test_pull_request_event(self):
        event = {
            "repository": {"full_name": "cufk/stemsplitter-macos"},
            "pull_request": {
                "head": {
                    "ref": "vibe/stemsplitter-1c69f9",
                    "sha": "def456",
                    "repo": {"full_name": "cufk/stemsplitter-macos"},
                }
            },
        }
        repo, branch, sha = parse_event(event)
        self.assertEqual((repo, branch, sha), ("cufk/stemsplitter-macos", "vibe/stemsplitter-1c69f9", "def456"))

    def test_garbage(self):
        self.assertEqual(parse_event({}), ("", "", None))
        self.assertEqual(parse_event({"ref": "refs/tags/v1"}), ("", "", None))


class SelfPushTests(unittest.TestCase):
    def test_self_push_detected(self):
        event = {"commits": [{"message": "fix(ci): automated fix [dev-agent]"}, {"message": "x [dev-agent]"}]}
        self.assertTrue(is_self_push(event))

    def test_human_push_not_self(self):
        event = {"commits": [{"message": "fix: something"}]}
        self.assertFalse(is_self_push(event))

    def test_no_commits(self):
        self.assertFalse(is_self_push({}))


class ExtractDiffTests(unittest.TestCase):
    def test_fenced_diff(self):
        text = 'Here is the fix:\n```diff\n--- a/Sources/x.swift\n+++ b/Sources/x.swift\n@@ -1 +1 @@\n-old\n+new\n```\n'
        diff = extract_diff(text)
        self.assertIsNotNone(diff)
        self.assertIn("--- a/Sources/x.swift", diff)
        self.assertIn("+new", diff)

    def test_raw_diff_fallback(self):
        text = "--- a/f.swift\n+++ b/f.swift\n@@\n-x\n+y"
        self.assertIn("+y", extract_diff(text))

    def test_no_diff(self):
        self.assertIsNone(extract_diff("I cannot fix this environmentally."))
        self.assertIsNone(extract_diff(""))


if __name__ == "__main__":
    unittest.main()
