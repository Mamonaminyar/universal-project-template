import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from validate_template import validate


class TemplateValidationTests(unittest.TestCase):
    def test_required_foundation_is_complete(self):
        failures = validate(ROOT)
        self.assertEqual([], failures)

    def test_readme_contains_universal_sections(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for marker in ("Purpose", "Design Goals", "Engineering Principles", "Baseline Validation"):
            self.assertIn(marker, readme)


if __name__ == "__main__":
    unittest.main()