# Tabula Documentation

Welcome to the Tabula documentation. This directory contains comprehensive documentation about the
Tabula browser tab management extension.

## Documentation Structure

### Product Documentation

- **Product Analysis** - Competitive analysis of similar products (Workona)
  including pricing tiers, features, and market positioning
- **Roadmap** - Product development roadmap with planned phases and features
- **User Stories** - Detailed user stories for all roadmap phases with
  acceptance criteria

### Technical Documentation

- **[Architecture Overview](architecture/overview.md)** - System architecture design, service
  selection, and infrastructure overview
- **[Specifications](architecture/specs.md)** - Detailed technical specifications for browser
  extension, API, database, and caching
- **[Non-Functional Requirements](architecture/nfr.md)** - Non-functional requirements including
  performance, scalability, reliability, security, and compliance

### Operator & Admin Documentation

- **[Operations Guide](guides/operations.md)** - Comprehensive guide for deploying, managing, and
  maintaining the Tabula platform
- **[Infrastructure Setup](reference/infrastructure.md)** - Detailed Terraform infrastructure setup
  and configuration guide
- **[CLI Reference](reference/cli.md)** - Reference documentation for `tabcli`, the administrative
  command-line tool

### API Documentation

- **[../api/openapi.yaml](../../tabula/api/openapi.yaml)** - OpenAPI 3.0 specification with complete API
  contract for all endpoints

## Quick Links

- [Main README](../../tabula/README.md) - Project overview and quick start
- [Contributing Guidelines](../../tabula/CONTRIBUTING.md) - How to contribute to Tabula
- [Infrastructure Setup](reference/infrastructure.md) - Terraform infrastructure documentation

## Getting Started

If you're new to Tabula, we recommend reading the documentation in this order:

1. Start with the [main README](../../tabula/README.md) to understand what Tabula is
2. Review the Product Analysis to understand our competitive landscape
3. Check the Roadmap to see where we're headed
4. Read User Stories for detailed feature requirements
5. Dive into [Architecture Overview](architecture/overview.md) for system design and infrastructure
6. Review [Specifications](architecture/specs.md) for detailed technical specifications
7. Check [Non-Functional Requirements](architecture/nfr.md) for performance and quality requirements
8. Explore the [OpenAPI spec](../../tabula/api/openapi.yaml) for API details
9. Review infrastructure documentation for deployment information

## For Developers

If you're contributing code to Tabula:

1. Read [CONTRIBUTING.md](../../tabula/CONTRIBUTING.md) for development setup and guidelines
2. Review [ARCHITECTURE.md](architecture/overview.md) to understand the system design
3. Check [SPECS.md](architecture/specs.md) for implementation details
4. Follow the [NFR.md](architecture/nfr.md) requirements for performance and quality
5. Reference USER_STORIES.md when implementing features
6. Use the [OpenAPI spec](../../tabula/api/openapi.yaml) as the API contract

## For Product Managers

If you're planning features or managing the roadmap:

1. Review ROADMAP.md for the current product plan
2. Check USER_STORIES.md for detailed requirements
3. Reference PRODUCT_ANALYSIS.md for competitive context
4. Use GitHub issue templates in ../.github/ISSUE_TEMPLATE for new
   features

## Contributing to Documentation

Documentation improvements are always welcome! Please see our
[Contributing Guidelines](../../tabula/CONTRIBUTING.md) for more information on how to submit documentation
updates.

When contributing to documentation:

- Keep language clear and concise
- Include examples where helpful
- Update related documents when making changes
- Check for broken links before submitting
- Follow the existing documentation structure

## Questions?

If you have questions that aren't covered in the documentation, please:

1. Check existing GitHub issues
2. Open a new issue with the `documentation` label
3. Reach out to the team

---

_Last updated: 2025-12-07_
