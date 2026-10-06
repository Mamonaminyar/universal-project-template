# Security Policy

## Scope

Projects created from this template must define their own security requirements based on data, users, dependencies, deployment model and regulatory obligations.

## Reporting Vulnerabilities

Do not disclose vulnerabilities through public issues. Use the derived project's private security reporting mechanism.

## Rules

- Never commit secrets, credentials, private keys or production configuration.
- Minimize permissions and use least privilege.
- Validate untrusted input.
- Keep dependencies and Actions updated.
- Review third-party integrations before granting access.
- Protect production environments and deployment credentials.
- Avoid sensitive data in logs, issue reports and CI output.
- Rotate compromised credentials immediately.

## Release Checklist

- [ ] Secrets are outside source control.
- [ ] Authentication and authorization are explicit.
- [ ] Dependencies and containers are reviewed.
- [ ] Logs do not expose sensitive data.
- [ ] Error handling does not leak secrets.
- [ ] Backup and recovery requirements are documented where applicable.
- [ ] Deployment permissions follow least privilege.