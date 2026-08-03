# Salesforce Development and Delivery

## Source of truth and environments

Git is the source of truth for deployable Salesforce metadata. Orgs execute and validate source; they must not merge concurrent issue branches. The release commit validated must be the release commit deployed.

| Purpose                | Alias               | Org type                   |
| ---------------------- | ------------------- | -------------------------- |
| Shared DEV and Dev Hub | `AxonFinanceDevHub` | Developer Edition          |
| Simulated production   | `AxonFinance`       | Separate Developer Edition |

The orgs have no Salesforce relationship. Git and CI/CD provide their promotion path. There is no UAT org; integrated functional validation happens in `AxonFinanceDevHub`.

## Branches

- `main` is the exact production baseline.
- `develop` is the shared integration baseline deployed to DEV.
- `feature/us-XXX` and `defect/bug-XXX` isolate issue development.
- `release/*` optionally selects only approved integration commits.
- `hotfix/*` starts from `main` and is merged back into `develop` after release.

Issue branches normally start from updated `develop`, synchronize with it before merge, and target `develop` in pull requests. Prefer squash merge so each issue creates one identifiable integration commit.

Never validate an issue in integrated `develop` and then promote its original issue branch directly to `main`.

## Standard flow

1. Create the issue branch from `develop`.
2. Develop locally; use a scratch org when the required source and dependencies can be provisioned.
3. Open a pull request to `develop`.
4. CI checks changed-file formatting and lint, runs LWC tests, and validates the Salesforce delta against DEV without persisting it.
5. Resolve metadata conflicts in Git.
6. Squash-merge the approved issue into `develop`.
7. CI deploys the merge delta to `AxonFinanceDevHub`.
8. Perform integrated functional validation in DEV.
9. Promote all approved changes through `develop → main`, or create `release/*` from `main` and apply only approved squash commits.
10. Manually run `Deploy Salesforce Production` with the full SHA currently deployed to production and the approved full SHA from `main`.
11. CI validates the exact delta in `AxonFinance` with local Apex tests and quick-deploys that same validated package.

If an issue fails in DEV, revert its merge commit in `develop` and let CI deploy the resulting delta. Never restore DEV by deploying an older issue branch.

## Current scratch-org constraint

`AxonFinanceDevHub` can create scratch orgs, but the current repository cannot yet provision the complete application into an empty org. The full-source test found missing dependencies, unsupported translations, and metadata that depends on the shape of the existing org.

For that reason, automated PR validation currently uses a check-only delta against DEV. Scratch-org automation can replace this gate after the repository contains a reproducible org definition, all required dependencies, and scratch-compatible metadata.

## GitHub Free public-repository configuration

Create these encrypted environment secrets under **Settings > Environments**:

- Environment `DEV`: `SALESFORCE_DEV_AUTH_URL`, generated from `AxonFinanceDevHub`.
- Environment `PROD`: `SALESFORCE_PROD_AUTH_URL`, generated from `AxonFinance`.

Never commit authentication URLs or place them in logs.

Protect `develop` and `main`, require pull requests, and require the `Lint and unit tests` and `Validate Salesforce delta` checks. Block force pushes and branch deletion.

Configure `PROD` with a required reviewer and restrict it to `main`. Production remains a manual `workflow_dispatch` operation requiring both immutable SHAs, and its secret is released only after environment approval.

## Delta deployment

Automatic workflows include only added, copied, modified, and renamed paths under `force-app`. LWC and Aura changes promote the complete bundle. Companion metadata files are collapsed into their source component when possible.

Deleted metadata is intentionally excluded. Deletion requires a reviewed destructive-change package, impact analysis, rollback planning, and explicit authorization.

Production requires two immutable SHAs:

- `base_sha`: the commit currently deployed in `AxonFinance`.
- `commit_sha`: the approved commit from `main`.

After successful deployment, retain the deployed `commit_sha` as the `base_sha` for the next release.
