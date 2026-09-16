---
title: "AXF-25 — Registrar realização preservando plano"
type: feature
created: "2026-09-07"
status: implemented-validated
review_loop_iteration: 0
contract_approval: approved
approved: "2026-09-08"
---

<frozen-after-approval reason="human-owned intent — scope approved by Michel on 2026-09-08">

## Intent

**Problema:** a AXF-25 exige baixa total/parcial e reversão, mas o contrato físico dessas alocações foi adiado para AXF-30. Um lookup/estado no lançamento não conserva múltiplas realizações nem seus snapshots.

**Approved approach:** Deliver the minimal allocation foundation for full/partial manual realization and immutable reversals in AXF-25, for later reuse by AXF-30. Preserve original plans, facts, derived residuals and recognition once. Include cash without a fabricated bank account. Require equal source/target currency; use AXF-24 only for reporting conversion. Preserve realization while reporting FX is pending. Authority: the active [AXF-25](https://axon-personal-finances.atlassian.net/browse/AXF-25) description and approval comment 10357.

## Boundaries & Constraints

**Sempre:** transação atômica; autorização nos dois lados; CRUD/FLS/sharing; nenhuma concessão Delete; versões esperadas, identidade por efeito e erros sanitizados. Fato manual não recebe ID Pluggy. Moeda, magnitude e parcelas planejadas nunca são sobrescritas. Mudanças de câmbio não recalculam histórico.

**Approval recorded:** Michel approved these scope decisions on 2026-09-08. Per-application recognition and the minimal allocation foundation belong to this story. Technical field names below remain implementation proposals to reconcile with repository conventions; this is not evidence that metadata exists or has been validated.

**Nunca:** criar FinancialEntry/SettlementTarget genéricos, matching automático, mecanismo de comandos universal, migração destrutiva ou promover develop para UAT/main. Conciliação N:N geral continua AXF-30.

## I/O & Edge-Case Matrix

| Cenário           | Entrada                                               | Resultado                                                                                                                                             |
| ----------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Parcial           | Plano 100 USD, fato 40 USD, taxa documental 5         | Realizado 40 USD/200 BRL; residual 60 USD; snapshot de 40, nunca 100                                                                                  |
| Total             | Plano 100; baixas 40 e 60                             | Realizado 100; residual zero; originais intactos                                                                                                      |
| Excesso           | Fonte disponível 30 ou alvo residual 30; tentativa 40 | Rejeitar; nenhum efeito parcial                                                                                                                       |
| Reversão          | Reverter baixa 40                                     | Nova compensação 40; original conservada; residual aumenta 40                                                                                         |
| Replay/disputa    | Mesma chave; payload diferente ou versão vencida      | Mesmo resultado ou CONFLICT; nunca duplicar                                                                                                           |
| Sem previsão      | ACTUAL_ONLY autorizado                                | Create financial representation/allocation atomically; create snapshot when rate exists, otherwise persist durable PENDING_FX without double counting |
| Acesso parcial    | Apenas fonte ou alvo acessível                        | Negar operação e dados privados, inclusive totais                                                                                                     |
| Sem cotação       | Reporting conversion rate absent                      | Preserve original realization and durable PENDING_FX; block dependent converted totals/actions; apply eligible FX idempotently later                  |
| Cash              | No bank/card                                          | Support explicit factual role without a fabricated account, self-reference or duplicate totals                                                        |
| Currency mismatch | Source and target original currencies differ          | Reject before allocation; no implicit settlement conversion                                                                                           |

</frozen-after-approval>

## Code Map

- `force-app/main/default/classes/AXF_CLS_FinancialEntryService.cls`: entrada FTX e validação do titular; reutilizar contratos, não alterar magnitude para reconhecer.
- `force-app/main/default/classes/ALT_CLS_FxConversionService.cls:188`: atualmente lê valor planejado; exige caminho específico para valor/data da alocação e replay do snapshot persistido.
- `force-app/main/default/classes/AXF_CLS_IdentityFraming.cls`: framing/hash existente.
- `force-app/main/default/objects/AXF_OBJ_BankAccountTransaction__c/fields/` e `AXF_OBJ_CreditCardTransaction__c/fields/`: magnitude, moeda, versão, origem e SourceKey já disponíveis.
- Evidência somente leitura: `ARCHITECTURE-SPINE.md:750,761` adia FinancialEntry; `SCHEMA-DICTIONARY.md:51,325` define RA conceitual e snapshot por finalidade/revisão.

## Tasks & Acceptance

All paths below are relative to `force-app/main/default/`. Scope is approved; new API names are technical implementation proposals and do not represent existing or deployed metadata.

**Implemented:**

- [x] Typed RA source references for BAT/CCT or an explicit CASH_FACT FTX, with a separate target. Manual sources use their own identity and never receive a fabricated Pluggy ID.
- [x] PLANNED / ACTUAL_ONLY / CASH_FACT roles; realization state, realized amount and residual derive from net allocations. No editable paid flag or financial rewrite is introduced. ACTUAL_ONLY has no projected residual.
- [x] Holder, target and source locking; operation key/payload comparison; expected versions; private conservation checks; fail-closed totals when any related effect or source is inaccessible.
- [x] Atomic applications, immutable full compensations per application, and original-field/delete guards. No invoice settlement side effect.
- [x] Per-application FX recognition through AXF-24. Snapshot replay reads frozen values before looking for rates. Selection respects side and the event date in the BCB Sao Paulo time zone, within the existing five-day lookback.
- [x] Durable PENDING_FX with original realization retained, unavailable converted totals, and explicit idempotent retry. A technical snapshot persistence failure rolls back the complete command. Reversals retain original snapshot evidence.
- [x] Dedicated controller, PT-BR/EN LWC, standalone tab and an optional record page. The source version is captured automatically. The record page is supplied for activation in App Builder; no default-page assignment or live deployment is performed.
- [x] Additive AXF_PS_Realization grants the explicit capability, CRUD/FLS and tab access, without Delete/ViewAll/ModifyAll. Existing Gestor/Participante groups include the permission set.
- [x] Focused Apex tests and LWC tests. Actual parallel session/load testing remains an explicit verification limit; stale versions, sequential competing requests, locks and conservation were checked.

## Design Notes

FTX realization state derives from net allocations. Cash without an account is in scope. Different source/target currencies are explicitly outside this delivery; reporting currency conversion remains in scope. Missing reporting FX does not reject a valid original realization.

### Implementation refinements under the approved scope

- **Dinheiro integra o escopo:** PRD `prd.md:183–184`, FR-35, define receitas/despesas em dinheiro e baixa manual com conta opcional. `ARCHITECTURE-SPINE.md:761` e `SCHEMA-DICTIONARY.md:48` permitem discutir FTX como fonte direta no lugar de FinancialEntry. Proposta: terceiro lookup `AXF_RA_LKP_ManualTransaction__c`, XOR com BAT/CCT, para FTX `ACTUAL_ONLY` de dinheiro distinto do FTX-alvo. Proibir autorreferência/ciclos; criar fonte/alvo/alocação atomicamente. Identificar papel factual explicitamente e excluir essa representação dos totais de plano para não duplicar consumo. Nenhuma conta bancária fictícia.
- **Baseline não oferece essa garantia:** Status é restrito a CONFIRMED/PLANNED; `AXF_FTX_NUM_Version__c` somente reserva lock futuro e o wizard inicializa 0. Não existe trigger FTX nem regra de imutabilidade ou autorreferência. ACTUAL_ONLY não existe na picklist atual. Não reutilizar CONFIRMED como prova de realização ou de papel factual. O contrato aprovado precisará distinguir esses papéis e proteger campos materiais via trigger.
- **Approved currency boundary:** Source and target must use the same original currency. AXF-24 converts to reporting currency only; it never permits source/target over-allocation. Cross-currency settlement remains with AXF-30/60/62 and would require separate original magnitudes/ISOs and exchange evidence. This boundary is now recorded in Jira, not awaiting confirmation.
- **Approved FX correction:** Preserve the original event in PENDING_FX when reporting FX is unavailable, then apply the first eligible bulletin under AXF-24 policy idempotently. Block dependent converted indicators/actions. A persistence failure rolls back the command, whereas a missing rate produces a valid durable pending state. The earlier proposal to reject all realization without a rate is superseded.

## Spec Change Log

- 2026-09-08: Michel approved full/partial realization, immutable reversal, per-application FX, legitimate cash, same source/target currency and preservation under missing reporting FX. Jira active criteria updated; comment 10357 preserves the previous definition. Implementation and validation remain outstanding.

## Verification

- `git diff --check`; análise estática do delta, Jest e testes Apex focados.
- Validação em AXON_DEV somente mediante coordenação do agente principal; nenhuma execução concorrente na org compartilhada.
- Conferir preservação de magnitudes/parcelas, ausência de efeitos parciais e acesso PT-BR/EN. Commit/PR develop e Jira somente após implementação validada.

### Validation evidence — 2026-09-09

- AXON_DEV check-only `0Afaj00000jfABBCA2`: Succeeded, 20 Apex tests passed, no component/test errors or coverage warnings.
- Coverage: RealizationService 97.5%, dedicated controller 95.3%, guard 89.0%, FxConversionService 85.8%, all affected triggers 100%.
- Cases include cash/bank/card, partial then total, source exhaustion, original-currency mismatch, ACTUAL_ONLY, replay, stale version, immutable originals, compensation, different application dates/FX sides, missing-rate recovery, reporting overflow rollback, denied capability and partial sharing under a Standard User profile.
- Jest 8/8 passed; ESLint passed. Code Analyzer: 0 severity 1/2 findings, 24 moderate and 30 low findings. Private conservation and trigger queries have documented narrow CRUD suppressions because integrity must include inaccessible historical effects.
- Reporting currency is the organization default in AXF_ReportCurrencyPref__c. It must be configured before realization; user presentation preferences cannot rewrite financial history.
- Latest develop AXF-101 changes were incorporated before publication. No production/UAT changes, deployment, merge or live parallel-session test is claimed.
