from pathlib import Path

REQUIRED_FILES = (
    "README.md",
    "LICENSE",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CHANGELOG.md",
    ".editorconfig",
    ".gitattributes",
    ".gitignore",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/CODEOWNERS",
    ".github/dependabot.yml",
    ".github/workflows/template-validation.yml",
    "config/project.yaml",
    "docs/PROJECT-CHARTER.md",
    "docs/ARCHITECTURE.md",
    "docs/DEVELOPMENT.md",
    "docs/OPERATIONS.md",
    "docs/DECISIONS.md",
    "docs/adr/0000-template.md",
)


def validate(root: Path) -> list[str]:
    failures: list[str] = []
    for relative in REQUIRED_FILES:
        if not (root / relative).is_file():
            failures.append(f"missing: {relative}")

    readme = (root / "README.md").read_text(encoding="utf-8") if (root / "README.md").is_file() else ""
    for marker in ("Purpose", "Design Goals", "Engineering Principles", "Baseline Validation"):
        if marker not in readme:
            failures.append(f"README missing section: {marker}")

    return failures


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    failures = validate(root)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print("PASS: universal project template validation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())