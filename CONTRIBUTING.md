# Contributing

Changes require a pull request, successful validation, and platform-owner review.

Before opening a pull request:

```bash
./scripts/validate.sh
```

Document every input, output, default, replacement risk, and security-boundary
change. A breaking input or resource-address change requires an upgrade note and
an appropriate Semantic Versioning release.

Never add customer-specific names, addresses, identifiers, sizing, credentials,
or state configuration to this repository.
