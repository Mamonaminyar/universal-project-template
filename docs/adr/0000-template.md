# ADR-0000: Use a Versioned Universal Project Foundation

## Status

Accepted

## Context

Projects benefit from a repeatable baseline for repository hygiene, documentation, security, validation and collaboration.

## Decision

Use this repository as a reusable foundation and adapt it to the actual technical and operational requirements of each project.

## Consequences

Positive:

- Faster initialization
- Consistent engineering standards
- Reusable security and collaboration controls
- Easier onboarding

Trade-offs:

- Generic files require project-specific customization.
- Project-specific build and deployment workflows must still be added.