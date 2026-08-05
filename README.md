<p align="center">
  <img width="940" alt="Axon Finance" src="https://raw.githubusercontent.com/mcarvall-labs/salesforce/main/resources/AxonPersonalFinancesLogo.png">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.pt-BR.md">Português</a></p>

# Axon Finance

Axon Finance is an open-source, Salesforce-native personal finance application. It brings bank accounts, credit cards, transactions, investments, loans, income, expenses, and cash-flow planning into one secure and extensible data model.

The project integrates with [Pluggy](https://pluggy.ai/) to synchronize financial data through Open Finance while keeping application credentials protected by Salesforce External Credentials and Named Credentials.

## Highlights

- Open Finance synchronization through the Pluggy API.
- Consolidated bank accounts, credit cards, invoices, transactions, investments, and loans.
- Income, expense, installment, financing, and cash-flow management.
- Lightning dashboards and actions built with Lightning Web Components.
- Secure server-side authentication—Pluggy secrets are never stored in Apex or browser code.
- Salesforce DX source format and automated validation with GitHub Actions.

## Install in Salesforce

> Install in a sandbox or Developer Edition first. Review the metadata and requested access before deploying to another organization.

<p align="center">
  <a href="https://githubsfdeploy.herokuapp.com?owner=mcarvall-labs&repo=salesforce&ref=main">
    <img alt="Deploy to Salesforce" src="https://githubsfdeploy.herokuapp.com/resources/img/deploy.png">
  </a>
</p>

The button uses the community-maintained GitHub Salesforce Deploy Tool. If your organization blocks third-party deployment tools, use the Salesforce CLI:

```bash
git clone https://github.com/mcarvall-labs/salesforce.git
cd salesforce
sf org login web --alias AxonFinance
sf project deploy start --source-dir force-app --target-org AxonFinance
sf org assign permset --name AXF_PS_User --target-org AxonFinance
```

After deployment, complete the Pluggy configuration below. Secrets are organization-specific and are intentionally not included in the repository or deployment.

## Configure Pluggy

### 1. Create your Pluggy account and application

1. Open the [Pluggy Dashboard](https://dashboard.pluggy.ai/) and create an account. Creating the account also creates a Team, where collaborators can be invited.
2. Open **Applications** and create an application for the desired environment.
3. Copy the generated `CLIENT_ID` and `CLIENT_SECRET`. Development and production applications have different credentials.

Treat both values as secrets. They grant access to financial data and must never be committed, pasted into an issue, or stored in frontend code. See Pluggy's official [API keys guide](https://docs.pluggy.ai/docs/get-your-api-keys).

### 2. Store the credentials in Salesforce

The deployment creates these metadata components:

| Component           | API name            | Purpose                                                             |
| ------------------- | ------------------- | ------------------------------------------------------------------- |
| External Credential | `AXF_EXC_Pluggy`    | Securely stores the Pluggy application parameters.                  |
| Named Credential    | `AXF_NC_Pluggy_API` | Defines the `https://api.pluggy.ai` endpoint used by Apex callouts. |
| Permission Set      | `AXF_PS_User`       | Grants application and External Credential principal access.        |

In Salesforce Setup:

1. Go to **Setup → Named Credentials → External Credentials**.
2. Open **AXF Pluggy External Credential** (`AXF_EXC_Pluggy`).
3. In the `AXF_Pluggy_Principal` named principal, enter the authentication parameters:
   - `clientId`: the Pluggy `CLIENT_ID`.
   - `clientSecret`: the Pluggy `CLIENT_SECRET`.
4. Save the principal parameters.
5. Confirm that **AXF Pluggy API** (`AXF_NC_Pluggy_API`) is enabled and points to `https://api.pluggy.ai`.
6. Assign **Axon Personal Finances - User** (`AXF_PS_User`) to every application user.

Axon Finance exchanges these credentials server-side for a short-lived Pluggy API key. Pluggy API keys expire after two hours; the application manages renewal and caching automatically.

## Requirements

- A Salesforce organization that supports Apex, Lightning Web Components, and Named Credentials.
- A Pluggy application with an active `CLIENT_ID` and `CLIENT_SECRET`.
- Salesforce CLI and Node.js 22+ only for local development or CLI installation.

## Local development

```bash
npm ci
npm run prettier:verify
npm run lint
npm run test:unit
```

```text
force-app/  Deployable Salesforce metadata
config/     Scratch-org configuration
docs/       Architecture and delivery documentation
scripts/    Salesforce, SOQL, Apex, and CI utilities
.github/    Issue templates and CI/CD workflows
```

See [Salesforce Development and Delivery](docs/SALESFORCE_DELIVERY.md) for the contribution and delivery workflow.

## Security and privacy

Financial information and API credentials are sensitive. Use least-privilege access, configure Salesforce sharing appropriately, test in a non-production organization, and never commit authentication URLs, credentials, tokens, exported customer data, `.env`, `.sf`, or `.sfdx` files.

To report a vulnerability, use GitHub's private security reporting feature when available; do not disclose exploitable details in a public issue.

## Contributing

Issues and pull requests are welcome. Keep changes focused, include relevant tests, and do not include personal financial data or secrets in examples, logs, commits, or screenshots.

## License and attribution

Licensed under the [Apache License 2.0](LICENSE) ([unofficial Brazilian Portuguese translation](LICENSE.pt-BR)). You may use, modify, and distribute this project under its terms. Redistributed copies and derivative works must preserve the required copyright, license, and attribution notices, including the contents of [NOTICE](NOTICE) ([Brazilian Portuguese version](NOTICE.pt-BR)).

Axon Finance is an independent open-source project and is not affiliated with or endorsed by Salesforce or Pluggy. Salesforce and Pluggy are trademarks of their respective owners.
