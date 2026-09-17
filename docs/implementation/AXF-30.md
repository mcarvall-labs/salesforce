# AXF-30 — Montar e confirmar uma conciliação N:N

Status: implementado na branch `feature/AXF-30-n-n-reconciliation` (base `sprint/sprint-4` @ `d758d43`).
Contrato normativo: `_bmad-output/planning-artifacts/architecture/architecture-Axon-Finance-2026-08-21/AXF-30-N-N-RECONCILIATION.md`
(ratificado em 17/09/2026) e os companions citados no seu frontmatter.

## O que foi entregue

| Artefato | Papel |
| --- | --- |
| `force-app/main/default/objects/AXF_OBJ_Reconciliation__c/` | Raiz ratificada `RCN` (AutoNumber `RCN-{000000}`, `sharingModel Private`, `enableHistory`, `enableSharing`) com os **8** campos do contrato |
| `.../AXF_OBJ_ReconciliationAllocation__c/fields/AXF_RA_LKP_Reconciliation__c.field-meta.xml` | Único campo novo do `RA`: Lookup para `RCN`, `deleteConstraint Restrict` (nunca Master-Detail) |
| `force-app/main/default/classes/ALT_CLS_ReconciliationService.cls` | Comando `reconciliation.allocation.confirm.v1`, leitura autoritativa e montagem consultiva |
| `force-app/main/default/classes/AXF_CLS_CTRL_ReconciliationWorkbench.cls` | Fronteira Apex→LWC (leitura cacheable, mutação sem cache, erro `{code, reasons}`) |
| `force-app/main/default/lwc/aXF_LWC_reconciliationWorkbench/` | Superfície list→review→confirm com tabela fonte/alvo/disponível/alocado/residual/moeda |
| `AXF_CT_ReconciliationWorkbench.tab-meta.xml` + `AXF_CA_AxonFinance.app-meta.xml` | Tab e registro na app Axon Finance |
| `customPermissions/AXF_CanConfirmReconciliation` | Capability de confirmação (concedida por `AXF_PS_GestorFinanceiro`) |
| `labels/CustomLabels.labels-meta.xml` + `translations/pt_BR.translation-meta.xml` | 80 labels `AXF_ReconciliationWorkbench_*` (en_US base + PT-BR) |
| `ALT_CLS_ReconciliationServiceTest` / `AXF_CLS_CTRL_ReconciliationWorkbenchTest` | Matriz I/O (GF-01..05, GF-72..75, moeda, autorização, versão, plano de lock, double-submit, residual) |

## Contratos seguidos (caminho:linha do contrato)

- **Raiz e extensão do `RA`** — `AXF-30-N-N-RECONCILIATION.md` §4 (`AXF_OBJ_Reconciliation__c` com os 8 campos; `RA` ganha só o lookup). O molde de raiz é o `EAS` (`AXF_OBJ_EconomicAllocationSet__c.object-meta.xml:1-23`).
- **Identidade** — `reconciliation-v1 = SHA-256(frame("reconciliation-v1", operationId, correlationId, sorted(factIdentities), sorted(targetIdentities)))`, implementada em `reconciliationKey()` com `AXF_CLS_IdentityFraming.key` (frame length-prefixed, `SCHEMA-DICTIONARY.md:159`).
- **Identidade da linha** — `alloc-v2 = SHA-256(frame("alloc-v2", fatoIdentidade, targetType, targetIdentity, economicKind))` (`IMPLEMENTATION-CONTRACTS.md:86`), implementada em `allocationIdentity()`. É passada a `ALT_CLS_RealizationService.Input.allocationIdentity`, de modo que cada `RA` tem identidade canônica independente da proposta/run.
- **Ordem de lock** — `AXF-30-N-N-RECONCILIATION.md` §4: token do agregado (20) → fatos BAT/CCT/FTX manuais (30) → alvos FTX (50) → RCN/RA (60), sempre por `Id` (o `FOR UPDATE` já implica ordem por `Id`; `ORDER BY` com lock é rejeitado pela plataforma). Um registro cujo rank só é descoberto ao ser lido (fato declarado como alvo, ou plano declarado como fato) aborta com `LOCK_PLAN_CHANGED`.
- **Atomicidade** — um único `Savepoint` em `confirm()`; qualquer rejeição faz `Database.rollback` e devolve erro tipado. Nenhuma linha parcial: provado por `gf02`, `currencyMismatch`, `inaccessibleTarget`, `aRecordDiscoveredInAnotherRank`.
- **Residual persistido** — `AXF_RCN_NUM_ResidualMagnitude__c` + `AXF_RCN_TXT_ResidualCurrency__c`; `0` em `CONFIRMED` sem sobra, lado alvo quando há sobra, nulo apenas no park de resultado desconhecido.
- **Escrita das linhas** — delegada a `ALT_CLS_RealizationService.apply` (AXF-25), que é a **única** porta de escrita de `RA` (`ALT_CLS_RealizationGuard.allocations` recusa qualquer outro contexto). Tipagem XOR, evidência FX de reconhecimento, conservação e bump otimista permanecem onde estavam.
- **`RESULT_UNKNOWN`** — reaproveita o contrato de Matching (GF-75) sem nono valor de picklist: `BLOCKED` com residual nulo, retry `CONFLICT` e resolução por consulta autoritativa (`resolveResult`).
- **Candidatos** — estado `CONSULTATIVE`, evidência independente por `ALT_CLS_MatchEvidence.evaluate` (AXF-139/140, `AXF-MATCHING@1.0.0`) e ordenação de apresentação por `ALT_CLS_MatchEvidence.OrderKey`; nada é selecionado, pontuado ou confirmado automaticamente.

## Julgamentos (e por quê)

1. **Identidade do alvo = `AXF_FTX_EXI_ClientRequestId__c`** (Text(36), required, unique, external ID) e não `AXF_FTX_EXI_PlanIdentityHash__c`. O `PlanIdentityHash` existe no repositório mas **não existe no org** `AXON_DEV` (a API de dados responde `INVALID_FIELD`; está em recycle bin/ausente), e o comando não pode depender de um campo indisponível. O `ClientRequestId` é identidade externa canônica (independente do run), o que preserva o contrato `alloc-v2` ("identidades externas canônicas, não record IDs"). O fallback para o `Id` do registro só ocorre se o campo vier em branco — impossível hoje, porque é obrigatório.
2. **`reconciliation-v1` sem `householdKey` e sem `CommandExecution`** — conforme §3/§4 do contrato ratificado (esses conceitos estão retirados do alvo).
3. **Escopo de idempotência** — `operationId + aggregateType(RCN) + AXF_RCN_EXI_ReconciliationKey__c + idempotencyKey` (`OPERATION-REGISTRY.md:52`). Os 8 campos ratificados não incluem campo de idempotency key, portanto a chave durável do escopo é a própria `ReconciliationKey` (que já contém o `CorrelationId`, reaproveitado no retry); o `idempotencyKey` é validado como não vazio e limitado a 80 caracteres. Double-submit com a mesma intenção devolve o resultado durável; payload divergente na mesma chave devolve `CONFLICT`.
4. **Marcador de resultado desconhecido** — o estado `BLOCKED` do GF-75 precisa ser distinguível de `BLOCKED` por falta de evidência material, e a picklist ratificada não aceita um nono valor. Regra explícita: **residual nulo = resultado do commit desconhecido**; `BLOCKED` por falta de evidência sempre persiste o residual calculado. Documentado nos próprios campos e no serviço.
5. **Residual do agregado = lado alvo** (soma dos residuais dos alvos, na moeda do alvo). O residual da fonte continua exposto por linha (`sourceResidual`): sobra de fonte é capacidade própria do fato, não obrigação em aberto deste agregado.
6. **Bump de versão por linha** — o AXF-25 incrementa a versão de alvo/fonte uma vez por linha aplicada (lock otimista). Duas linhas sobre o mesmo fato deixam a versão em 2; cada contribuição continua contada exatamente uma vez (asserção explícita em `gf01`).
7. **`fieldPermissions` dos campos obrigatórios** — a spec pede FLS dos 8 campos do `RCN` em `AXF_PS_GestorFinanceiro`; a plataforma recusa deploy de FLS em campo `required` ("You cannot deploy to a required field") e o próprio repositório não lista campos obrigatórios nos PS. Foram concedidos explicitamente os três campos opcionais (`DT_EffectiveAt`, `NUM_ResidualMagnitude`, `TXT_ResidualCurrency`); os cinco obrigatórios (`PKL_State`, `NUM_Version`, `EXI_ReconciliationKey`, `TXT_CorrelationId`, `TXT_PolicyVersion`) são acessíveis por construção.
8. **`evidenceCoverage` do `ALT_CLS_EvidenceQueryService`** — a linha `RECONCILIATION`, antes `GAP_NOT_INTEGRATED`, passa a `COVERED_IMMUTABLE_SNAPSHOT` apontando o `RCN`, com flags derivadas do schema real (`actor=false`, `instant=true`, `source=true` (CorrelationId), `reason=false`, `priorState=true`). A superfície de *consulta* dedicada ainda não é exposta ali — declarado no próprio `limitNote`.

## Limitações conhecidas

- **Identidade de par é única**: `AXF_RA_EXI_AllocationKey__c` é único, então o mesmo par fato→alvo não pode receber uma segunda aplicação ativa; um complemento exige reverter a anterior (comportamento ratificado no contrato `alloc-v2`, `IMPLEMENTATION-CONTRACTS.md:87`).
- **N:N entre fatos e alvos**: o plano aceita vários fatos e vários alvos, mas cada linha carrega um fato e um alvo, e a conservação é validada por fato e por alvo (não há rateio implícito).
- **Conversão cambial**: moeda divergente sem evidência material é `CURRENCY_MISMATCH`; nenhuma paridade ou taxa é presumida (o indicador fica retido, como pede a matriz de I/O).
- **Reversão não reescreve o agregado**: `ALT_CLS_ReconciliationReversalService` cria a compensatória sem tocar o `RCN`; a releitura autoritativa (`resolveResult`) é quem recomputa o estado derivado e o residual persistido.
- **`AXF_FTX_EXI_PlanIdentityHash__c`** continua ausente do org `AXON_DEV` (dívida de schema pré-existente, referenciada por outras classes já entregues); reimportar esse campo exige decisão sobre o org compartilhado, fora do escopo desta entrega.

## Verificação executada

Commands e resultados: ver a seção de verificação do relatório de entrega (deploy `Succeeded`, testes Apex `23/23`, Jest `33 suítes / 271 testes`, Prettier sem violações no conteúdo commitado em LF, `trigger-handler-boundary` e os testes de CI em `node --test`).
