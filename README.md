<img width="940" height="353" alt="Axon Finance" src="https://raw.githubusercontent.com/axon-personal-finances/salesfoce/main/resources/AxonPersonalFinancesLogo.png" />

# Axon Finance

Axon Finance is a Salesforce application for personal financial management and Open Finance integration. It consolidates accounts, credit cards, transactions, investments, loans, revenues, expenses, and cash-flow forecasts in a single Salesforce data model.

## Main capabilities

- Open Finance synchronization through the Pluggy API.
- Bank-account and credit-card reconciliation.
- Income, expense, installment, financing, and consortium management.
- Cash-flow dashboards built with Lightning Web Components.
- Salesforce-native authentication through Named Credentials and External Credentials.

## Technology

- Salesforce Lightning Platform
- Apex
- Lightning Web Components
- Salesforce DX source format
- GitHub Actions for validation and deployment

## Repository structure

```text
force-app/       Deployable Salesforce metadata
manifest/        Metadata manifests
scripts/         Salesforce, SOQL, Apex, and CI utilities
config/          Scratch-org project definition
docs/            Architecture and delivery documentation
.github/         Issue templates and CI/CD workflows
```

## Local setup

Prerequisites:

- Node.js 22 or later.
- Salesforce CLI (`sf`).
- Access to a Salesforce development org.

Install the development dependencies:

```bash
npm ci
```

Authenticate a development org:

```bash
sf org login web --alias AxonFinanceDevHub
```

Deploy a specific source path:

```bash
sf project deploy start --source-dir force-app/main/default/<metadata-path> --target-org AxonFinanceDevHub
```

Do not commit authentication URLs, API keys, local Salesforce state, or environment files.

## Delivery

Development changes are integrated through `develop` and automatically deployed to the development org. Approved releases are promoted to `main` and deployed to production through the manually approved production workflow.

See [Salesforce Development and Delivery](docs/SALESFORCE_DELIVERY.md) for the complete process.

## External documentation

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli)
- [Pluggy API](https://docs.pluggy.ai/reference/)
