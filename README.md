# Bastion Aptos

A comprehensive monorepo for Bastion on Aptos blockchain.

## Overview

Bastion Aptos is a full-stack blockchain application built on the Aptos network. This monorepo contains all components needed to build, deploy, and maintain the platform.

## Repository Structure

```
bastion-aptos/
├── move/              # Aptos Move smart contracts
├── packages/
│   └── sdk-ts/        # TypeScript SDK
├── backend/           # Node.js backend services
├── web/               # React + TypeScript web application
├── infra/             # Infrastructure as Code (Terraform, scripts)
├── docs/              # Documentation
└── .github/           # GitHub Actions workflows and configurations
```

## Getting Started

### Prerequisites

- Node.js >= 18.x
- npm or yarn
- Aptos CLI (for Move development)
- Terraform (for infrastructure)

### Installation

```bash
# Clone the repository
git clone https://github.com/kunal-drall/bastion-aptos.git
cd bastion-aptos

# Install dependencies for all packages
npm install
```

### Development

Each directory contains its own README with specific instructions:

- [Move Contracts](./move/README.md)
- [TypeScript SDK](./packages/sdk-ts/README.md)
- [Backend Services](./backend/README.md)
- [Web Application](./web/README.md)
- [Infrastructure](./infra/README.md)
- [Documentation](./docs/README.md)

## Contributing

We welcome contributions! Please see our [Contributing Guide](./docs/CONTRIBUTING.md) for details.

## Security

For security concerns, please review our [Security Policy](./SECURITY.md).

## Code Owners

This repository uses [CODEOWNERS](./.github/CODEOWNERS) to manage code review assignments.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](./LICENSE) file for details.

## CI/CD

This repository uses GitHub Actions for continuous integration and deployment:

- **Build Pipeline**: Builds all packages and checks for compilation errors
- **Test Pipeline**: Runs unit and integration tests
- **Deploy Pipeline**: Deploys to staging and production environments

See [.github/workflows](./.github/workflows) for workflow definitions.

## Support

For questions and support, please:
- Open an issue on GitHub
- Check the [documentation](./docs/)
- Join our community discussions