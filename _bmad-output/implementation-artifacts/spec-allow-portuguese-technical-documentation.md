---
title: 'Allow Portuguese Technical Documentation'
type: 'chore'
created: '2026-08-20'
status: 'done'
baseline_commit: 'eaf229f8517a2da8b808a7e080e7b5f2a63bb524'
review_loop_iteration: 0
context:
  - '{project-root}/.ai/CORE.md'
  - '{project-root}/.ai/PERSONAL_RULES.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The project-specific language rule currently requires technical documentation, pull requests, and Jira content to be written in English. That requirement is obsolete for Axon Finance and leaves existing Jira and Confluence content inconsistent with the project's PT-BR working language.

**Approach:** Amend the canonical project rule so technical documentation is written in PT-BR by default, with English allowed when explicitly requested or required by the intended audience. Require pull requests and Jira content in PT-BR, preserve English for source-code identifiers, Salesforce metadata developer names, and commits, then translate existing Axon Finance Jira and Confluence content into PT-BR.

## Boundaries & Constraints

**Always:** Keep chat responses, pull-request content, Jira content, and technical documentation in PT-BR by default. Keep source-code identifiers, Salesforce metadata developer names, and commit messages in English. Allow technical documentation in English only when explicitly requested or required by its intended audience. Preserve identifiers, keys, URLs, code blocks, commands, acceptance-criteria meaning, issue relationships, workflow state, authorship, timestamps, and other operational metadata during translation.

**Ask First:** Any future proposal to change the English requirements for source code, Salesforce metadata developer names, or commit messages requires explicit user approval. Any Jira or Confluence item whose translation would alter business meaning rather than language alone must be reported and left unchanged until clarified.

**Never:** Do not edit `.ai/CORE.md`, `.ai/PERSONAL_RULES.md`, BMAD configuration, generated workflow snapshots, existing local product artifacts, or unrelated working-tree changes as part of this request. Do not translate historical GitHub pull requests retroactively. Do not change Jira workflow state, assignments, relationships, acceptance intent, or Confluence page topology while translating content.

</frozen-after-approval>

## Code Map

- `.ai/PROJECT_RULES.md:243-249` -- Canonical, highest-precedence project-specific language and translation rules; local implementation target.
- `.ai/CORE.md:195-201` -- Generic rule already defers technical-documentation language to project rules; read-only evidence.
- `.ai/PERSONAL_RULES.md:4-7` -- Personal default already permits project rules to override English technical documentation; read-only evidence.
- `_bmad/config.toml:15` -- Separate BMAD document-output default remains English and is explicitly outside this narrowly requested change.
- `Jira AXF on axon-personal-finances.atlassian.net` -- Authoritative work-item content to inventory and translate into PT-BR without changing workflow metadata.
- `Confluence AXF on axon-personal-finances.atlassian.net` -- Authoritative product-documentation content to inventory and translate into PT-BR without changing page topology.

## Tasks & Acceptance

**Execution:**
- [x] `.ai/PROJECT_RULES.md` -- Replace the obsolete English-only rule so technical documentation defaults to PT-BR, pull requests and Jira content use PT-BR, and code, Salesforce metadata developer names, and commits remain in English.
- [x] `Jira AXF` -- Authenticate against the canonical Axon Finance site, inventory existing issues and relevant text fields, translate English content into PT-BR, and read updated items back to verify language and semantic preservation.
- [x] `Confluence AXF` -- Authenticate against the canonical Axon Finance site, inventory existing pages, translate English page content into PT-BR, and read updated pages back to verify language, formatting, links, and semantic preservation.
- [x] `.ai/PROJECT_RULES.md` -- Review the surrounding language section and final repository diff to confirm unrelated rules and working-tree changes remain untouched.

**Acceptance Criteria:**
- Given an agent is producing technical documentation for Axon Finance and the user has not specified a language, when the project language rules are applied, then PT-BR is selected by default.
- Given the user or intended audience explicitly requires English documentation, when the project language rules are applied, then English remains permitted.
- Given source code, Salesforce metadata developer names, or commit messages are produced, when the updated rule is applied, then they remain in English.
- Given a pull request or Jira item is created or updated, when the updated rule is applied, then its human-readable content is written in PT-BR with UTF-8-safe formatting.
- Given existing Axon Finance Jira issues contain English prose, when the migration completes, then their human-readable content is in PT-BR while keys, statuses, assignments, relationships, code, and requirement meaning are preserved.
- Given existing Axon Finance Confluence pages contain English prose, when the migration completes, then their human-readable content is in PT-BR while page hierarchy, formatting, links, code, and meaning are preserved.
- Given the repository rule is updated, when the final diff is inspected, then only `.ai/PROJECT_RULES.md` contains the requested local implementation change and unrelated working-tree changes remain untouched.

## Verification

**Commands:**
- `rg -n -A 6 -B 2 "Language and translations" .ai/PROJECT_RULES.md` -- expected: the section permits PT-BR or English technical documentation and retains all neighboring rules.
- `git diff -- .ai/PROJECT_RULES.md` -- expected: one focused language-rule change with no unrelated edits.
- `Jira read-back through the project-local jira-axon connector` -- expected: every translated issue preserves its key, workflow metadata, relationships, formatting, and requirement meaning.
- `Confluence read-back through the canonical Axon Finance connector` -- expected: every translated page preserves its ID, hierarchy, formatting, links, code, and meaning.

## Suggested Review Order

- Start with the canonical language boundary and its preserved machine-readable exceptions.
  [`PROJECT_RULES.md:243`](../../.ai/PROJECT_RULES.md#L243)
