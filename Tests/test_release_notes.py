import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

source = Path(__file__).resolve().parents[1] / ".github/scripts/generate_release_notes.py"
spec = importlib.util.spec_from_file_location("release_notes", source)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class ReleaseNotesTests(unittest.TestCase):
    def test_publish_requires_existing_notes_before_contacting_github(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(notes, "get_gh_footer", return_value="Footer") as footer:
            output = Path(tmp) / "notes.md"
            args = ["--append-github-footer", "--tag", "v2.0.0", "--prev-tag", "", "--output", str(output)]
            for contents in (None, b"", b" \n\t"):
                with self.subTest(contents=contents):
                    if contents is not None:
                        output.write_bytes(contents)
                    self.assertNotEqual(notes.main(args), 0)
                    footer.assert_not_called()
                    if contents is None:
                        self.assertFalse(output.exists())
                    else:
                        self.assertEqual(output.read_bytes(), contents)

    def test_publish_appends_only_the_github_footer(self):
        github = "## What's Changed\n- Fix UI\n## New Contributors\n- @new\n\n**Full Changelog**: url"
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "notes.md"
            output.write_text("Manual notes\n", encoding="utf-8")
            with patch.dict(notes.os.environ, GH_TOKEN="test"), patch.object(notes.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, json.dumps({"body": github}), "")
                args = ["--append-github-footer", "--repo", "owner/repo", "--tag", "v2.0.0",
                        "--prev-tag", "v1.0.0", "--output", str(output)]
                self.assertEqual(notes.main(args), 0)
                self.assertEqual(run.call_args.args[0], ["gh", "api", "repos/owner/repo/releases/generate-notes",
                                                        "-f", "tag_name=v2.0.0", "-f", "previous_tag_name=v1.0.0"])
                expected = "Manual notes\n\n## New Contributors\n- @new\n\n**Full Changelog**: url\n"
                self.assertEqual(output.read_text(encoding="utf-8"), expected)
                run.return_value = subprocess.CompletedProcess([], 1, "", "API unavailable")
                self.assertEqual(notes.main(args), 0)
                self.assertEqual(output.read_text(encoding="utf-8"), expected)

    def test_manual_notes_take_priority(self):
        manual = "<!-- changelog:ru -->\nИсправлен лог\n<!-- /changelog:ru -->"
        body = notes.build_release_body("v1.0.3", "owner/repo", "https://github.com",
                                        manual, "unused AI summary", "- fix log", "")
        self.assertIn(manual, body)
        self.assertNotIn("unused AI summary", body)
        for arch in ["arm64", "x86_64"]:
            self.assertIn(f"releases/download/v1.0.3/WarpScout-macOS-{arch}.zip)", body)
        self.assertNotIn(".sig", body)

    def test_provider_response_and_fallback(self):
        payload = {"choices": [{"message": {"content": json.dumps({
            "ru": {"fixed": ["Исправлен лог"]}, "en": {"fixed": ["Fixed log"]}
        })}}]}
        with patch.object(notes.urllib.request, "urlopen") as request:
            response = request.return_value.__enter__.return_value
            response.read.return_value = json.dumps(payload).encode()
            summary = notes.generate_ai_notes("v1.0.3", "fixture", "test", "https://example.invalid", "test")
            self.assertIn("<!-- changelog:ru -->", summary)
            self.assertIn("<!-- changelog:en -->", summary)
            response.read.return_value = b"{}"
            self.assertIsNone(notes.generate_ai_notes("v1.0.3", "fixture", "test", "https://example.invalid", "test"))
        body = notes.build_release_body("v1.0.3", "owner/repo", "https://github.com", "", None, "- fix log", "")
        self.assertIn("<!-- changelog:all -->", body)
        self.assertIn("- fix log", body)
