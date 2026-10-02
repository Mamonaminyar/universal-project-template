# Release Policy

## Versioning

This project uses Semantic Versioning:

MAJOR.MINOR.PATCH

MAJOR
Incompatible or breaking changes.

MINOR
Backward-compatible functionality.

PATCH
Backward-compatible fixes and maintenance.

Pre-release versions use:

- alpha
- beta
- rc

Examples:

- v1.0.0
- v1.2.0
- v1.2.3
- v2.0.0-rc.1

## Release Rules

Releases must:

1. originate from the protected main branch;
2. pass required CI checks;
3. pass CodeQL/security checks;
4. satisfy DCO requirements;
5. have an updated changelog when applicable;
6. use an immutable Git tag;
7. include release notes;
8. identify breaking changes explicitly.

## Tagging

Stable releases use:

MAJOR.MINOR.PATCH

Pre-releases use:

MAJOR.MINOR.PATCH-alpha.N
MAJOR.MINOR.PATCH-beta.N
MAJOR.MINOR.PATCH-rc.N

## Existing Release

0.1.0 is an existing immutable foundation release and must not be recreated or rewritten.

Future releases must increment the version from the latest valid release.

## Release Integrity

A release is considered valid only when the tagged commit corresponds to the intended release commit on main and all required repository controls have passed.
