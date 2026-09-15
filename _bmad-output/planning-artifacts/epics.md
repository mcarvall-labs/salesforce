---
stepsCompleted:
  - step-01-validate-prerequisites
inputDocuments:
  - C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/SPEC.md
  - C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/brownfield.md
  - C:/Projects/Axon Finance/_bmad-output/specs/spec-axon-finance/traceability.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/prds/prd-Axon-Finance-2026-08-20/prd.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/ux-designs/ux-Axon-Finance-2026-08-21/DESIGN.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/ux-designs/ux-Axon-Finance-2026-08-21/EXPERIENCE.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/ARCHITECTURE-SPINE.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/SCHEMA-DICTIONARY.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/IMPLEMENTATION-CONTRACTS.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/OPERATION-REGISTRY.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/SHARING-MATRIX.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/OPERATIONS-CONTRACT.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/GOLDEN-FIXTURES.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/DEVELOPER-GUIDE.md
  - C:/Projects/Axon Finance/_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/reviews/REVIEW-CONSOLIDATED.md
  - C:/Projects/Axon Finance/Salesforce/force-app/main/default
---

<!-- AXF-106-DECISION-20260912 -->
## AXF-106 — current bank and holder decision (2026-09-12)

Traceability: AXF-106 is the owner of the new decision. Open epic integration: AXF-1/10/26/34/58/81; installation/migration: AXF-77/78/79; source consumers adopt scoped supplements in Jira. Completed story requirements are historical baseline, not silently rewritten.

Decision approved by Michel on 2026-09-12; authoritative scope: AXF-106. This active supplement supersedes conflicting bank-reference and onboarding-order assumptions in this document only. It is a requirement change, not evidence of implementation, migration or deployment.

Reuse the Financial Institution object reported in production as the canonical bank directory. Its exact API name/schema and availability in DEV/UAT still require read-only verification. Do not create a duplicate object or infer schema from a label.

Connections select Bank through a Lookup to that directory and a suggested Holder through a Lookup to Account (AXF_Person / AXF_Business). Register/reuse holders before connections; provide inline New holder without losing Item ID or bank selection. Holder registration creates no User and grants no access.

Bank accounts, credit cards, manual-source forms and relevant selectors, filters, reports and integrations consume canonical institution references. Preserve provider connector/institution text and IDs separately. MeuPluggy, name similarity or bank equality never proves bank mapping, source identity or ownership.

Connection holder remains a suggestion. Confirm the holder per account/card through AXF-85 before financial use. Editing connection references must not rewrite confirmed holders, grants, financial facts, allocations or immutable document/archive snapshots.

Display bank and holder names plus masked Item ID; support multiple connections sharing bank/holder, explicit edits, idempotent registration and rediscovery. Existing missing references remain visible pending decisions. An alias-only solution does not satisfy this decision.

Inventory consumers before migration; map only unambiguous associations, report unresolved/conflicting mappings, preserve original values and require repeatable backfill and rollback. Do not delete legacy fields until consumers and parity checks pass. Production mutation and destructive cutover require separate authorization.

Open implementation decisions: verified institution identifiers; mandatory fields/progression gates; inactive/deleted-reference policy; and connections with sources from different banks. Do not impose a blanket required-field retrofit or invent a new automatic mapping rule.

Preserve Dev Done and later work-item history. AXF-106 owns the evolution of delivered AXF-80/84/85/86/88/89/90/91/98. Related open work receives only its applicable compatibility obligations; unrelated reviewed contracts/readiness are not reopened.

Canonical page: https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3702785

Requirements: https://axon-personal-finances.atlassian.net/browse/AXF-106

<!-- /AXF-106-DECISION-20260912 -->


# Axon Finance - Epic Breakdown

## Overview

Este documento de planejamento referencia, sem redefinir, os contratos canônicos do Axon Finance. A redação normativa integral de cada requisito permanece no PRD e nos companions indicados em `inputDocuments`.

## Requirements Inventory

### Functional Requirements

- FR-1–FR-8: autorização, sincronização, importação, preservação de fonte, correção, auditoria, saúde e ownership de dados (CAP-1/CAP-5/CAP-8).
- FR-9–FR-15: planejamento, capacidade segura, cenários, reservas, obrigações, confirmação material e câmbio rastreável (CAP-2/CAP-6).
- FR-16–FR-19: candidatos, confirmação/reversão, alocação N:N, resíduos e transferências internas (CAP-3).
- FR-20–FR-23 e FR-50: Entidades, ownership, consolidação, administração, colaboração e alocação econômica compartilhada (CAP-5).
- FR-24–FR-30: orçamento, metas, dívidas, painel decisório, atualidade, indicadores reproduzíveis e exceções auditadas (CAP-6/CAP-8).
- FR-31–FR-34: expansão versionada de CSV, investimentos, evolução fiscal e assistência inteligente, todos preservados como pós-MVP quando indicado.
- FR-35–FR-36: Fluxo de Caixa manual e conversão rastreável de transação externa.
- FR-37–FR-48: Faturas, calendário efetivo, parcelas, pagamentos, cinco dimensões de estado, financiamento, contestação, residual e saldo credor (CAP-4).
- FR-49: retenção, exportação, encerramento, revogação, exclusão autorizada e legal hold (CAP-8).
- FR-51–FR-60: Contraparte, Contrato, versões efetivas, geração, trabalho, snapshots, emissão, entrega, arquivo e conciliação documental (CAP-10).
- FR-61–FR-63: liquidação cambial, encargos explícitos, confirmação, conservação e compensação (CAP-3).

Identidade e texto integral: `prd.md` §§4.1–4.9; cobertura claim-by-claim: `traceability.md` §Requisitos funcionais.

### NonFunctional Requirements

- NFR-1: isolamento entre Household/Financial Entity.
- NFR-2: menor privilégio com CRUD/FLS, sharing e autorização de domínio.
- NFR-3: idempotência namespaced, vinculada ao payload e retida pelo período normativo.
- NFR-4: importação atômica, visível e recuperável.
- NFR-5: preservação da fonte original.
- NFR-6: recuperabilidade e falha acionável.
- NFR-7: auditabilidade material.
- NFR-8: explicabilidade de cálculos e recomendações.
- NFR-9: Salesforce web/mobile como superfície MVP.
- NFR-10: baseline protegida por compatibilidade, migração, regressão e rollback.
- NFR-11: reconhecimento econômico único.
- NFR-12: conservação de valor, moeda, resíduos e arredondamento explícitos.
- NFR-13: MFA/step-up e evidência para acesso privilegiado.
- NFR-14: autorização em todas as superfícies, comprovada por testes negativos.
- NFR-15: backup diário, RPO 24h, RTO 8h, retenção 90 dias e restore trimestral.
- NFR-16: SourceIdentity determinística, versionada, com alias e revisão segura.
- NFR-17: revogação convergente e fail-closed em caches, shares, links, buscas, relatórios, arquivos, exports e async.
- NFR-18: expected version, serialização de roots, lock ordering e `RESULT_UNKNOWN`.
- NFR-19: budgets de capacidade, backpressure e trabalho retomável.
- NFR-20: correlação, progresso, tentativas, causa sanitizada, SLO e alerta operacional.
- NFR-21: compatibilidade N/N-1, rollout, drift reconciliation e rollback não destrutivo.

Texto integral: `prd.md` §5; cobertura: `traceability.md` §Requisitos não funcionais.

### Additional Requirements

- AD-1–AD-39 permanecem vinculantes; histórias citam e não redefinem decisões.
- `Account` não pertence ao target state; somente compatibilidade transitória expand → migrate → contract é permitida. Nenhuma remoção integra este planejamento.
- O modelo físico, estados, algoritmos, OperationIds, sharing, budgets, release gates e fixtures vêm exclusivamente dos companions normativos.
- Preservar `AXF_`, `AXF_OBJ_`, `AXF_CLS_CTRL_`, `ALT_CLS_`, `AXF_TRG_`, `AXF_FLW_` e `aXF_LWC_` conforme regras locais.
- Direção obrigatória: LWC → controller dedicado `AXF_CLS_CTRL_` → serviço reutilizável `ALT_CLS_` → dados/integrações.
- Migração por fases: Inventory/Safety, Expand, Backfill/Dual Compatibility, Authority Cutover, Observation/Parity e Contract/Legacy Removal.
- Apex 67.0 exige inventário e substituição controlada por `WITH USER_MODE`/`AccessLevel.USER_MODE`, com elevação isolada e justificada.
- Toda mutação material usa command envelope, OperationId, idempotency scope, expectedVersion, correlationId, payload hash, audit e lock ordering canônicos.
- Pluggy usa staging por Financial Account, confirmação atômica, SourceIdentity v1, alias verificado, reconexão segura e contract tests.
- Multiple Currencies é irreversível e exige inventário, default explícito, backfill, quarentena e parity gate antes de ativação/cutover.
- Segurança é deny-by-default, inclui share projector/reconcile, invalidação transacional e convergência observável.
- Observabilidade, retenção, capacidade, release, rollback, recovery e archive proof seguem `OPERATIONS-CONTRACT.md` e `IMPLEMENTATION-CONTRACTS.md`.
- Golden Fixtures GF-01–GF-53 são evidência obrigatória conforme o mapa CAP → AD → testes.

### UX Design Requirements

- UX-DR1: implementar navegação e IA por Household/Financial Entity sem remover contexto material.
- UX-DR2: usar Lightning Base Components e SLDS; tokens visuais derivam de `DESIGN.md`.
- UX-DR3: representar loading, empty, stale, partial, blocked, conflict, result unknown, success e failure como estados explícitos.
- UX-DR4: fornecer confirmação server-side para ações materiais com resumo, consequência, escopo e step-up aplicável.
- UX-DR5: erros usam envelope seguro, orientação acionável e nenhuma PII, segredo ou stack trace.
- UX-DR6: controles cumprem teclado, foco visível, labels, descrição, anúncios e semântica de tabela/dados densos.
- UX-DR7: todas as jornadas passam WCAG 2.2 AA, zoom e largura de 320 CSS px.
- UX-DR8: mobile preserva informação e ação material; adaptação responsiva não oculta risco ou confiança.
- UX-DR9: progresso async é anunciável, retomável e distingue backpressure, bloqueio, cancelamento e resultado desconhecido.
- UX-DR10: revogação, sessão expirada, offline e artefatos derivados falham fechados.
- UX-DR11: UJ-1–UJ-10 permanecem os testes comportamentais end-to-end.

### FR Coverage Map

{{requirements_coverage_map}}

## Epic List

{{epics_list}}
