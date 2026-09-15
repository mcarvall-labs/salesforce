# Recomendação — próximo item do backlog AXF (2026-09-06)

> Memo gerado com base em evidência do repositório (branch `develop` @ 44f6475) e artefatos
> locais. **O Jira (projeto AXF) é a fonte autoritativa de prioridade e não estava acessível
> nesta sessão** (sem MCP/configuração do Jira). Confirmar a ordem antes de iniciar a implementação.

## Estado atual (evidência no repo)

- **Epic 7 — Contratos (AXF-50):** esteira consolidada em `develop` via PR #74
  (AXF-51 contraparte/relação, AXF-52 contrato rascunho, AXF-53 TermVersion ativa/imutável,
  AXF-54 modelos de remuneração, AXF-56 work records). Objetos presentes:
  `AXF_OBJ_Contract__c`, `AXF_OBJ_ContractTermVersion__c`, `AXF_OBJ_Counterparty__c`,
  `AXF_OBJ_CounterpartyTaxIdentifier__c`, `AXF_OBJ_CounterpartyEntityRelationship__c`,
  `AXF_OBJ_WorkRecord__c`, `AXF_OBJ_FinancialTransaction__c`.
- **Faltam no epic 7:** AXF-55 (Revisar e publicar a agenda contratual) e AXF-57 (Preservar
  snapshot e overrides da aplicação contratual) — nenhum commit/mensagem/objeto novo os referencia.
- **Epic 2 — Fontes:** AXF-12 (Sincronizar fontes) entregue como **1/N** (PRs #75/#76): schema
  `AXF_OBJ_CreditCardTransaction__c` (CCT), CMT `AXF_PluggySyncPolicy__mdt` + registro Default
  (params AC8), produto `INR`. As fatias seguintes (2/N…) não têm evidência local de escopo.
- **Roadmap local (sprint-status.yaml / jira-sprint-planning-source.md, gerados 26/08):** estão
  desatualizados quanto ao ritmo real (entrega por demanda); servem apenas como mapa de títulos.
  AXF-55/AXF-57 estão previstos na mesma esteira do epic 7.

## Recomendação

**Próximo item: AXF-55 — Revisar e publicar a agenda contratual** (epic 7, AXF-50).

Justificativa (repo-based, a confirmar no Jira):
1. **Continuidade da esteira:** AXF-51…56 acabaram de entrar em `develop` (#74). AXF-55 é o
   próximo passo canônico do ciclo de vida descrito no próprio doc de AXF-52 (transições
   autoritativas para ACTIVE pertencem a AXF-53/54/55) — manter o contexto quente reduz custo.
2. **Pré-requisito em cadeia:** AXF-57 (snapshot/overrides) depende semanticamente da publicação
   da agenda (AXF-55); fechar o epic na ordem 55 → 57 é o caminho mais barato.
3. **Alternativas maiores:** AXF-12 (2/N) é um epic paralelo grande (esteira de sincronização
   CCT/SyncPolicy/INR) que provavelmente exige decisões de política (parâmetros AC8 já aprovados
   em #76) — bom segundo candidato, mas com mais incerteza de escopo sem a spec do Jira.

## Candidatos em ordem sugerida

| # | Item | Por quê | Evidência |
|---|------|---------|-----------|
| 1 | AXF-55 — Revisar e publicar a agenda contratual | fecha o ciclo iniciado em #74; contexto quente | doc AXF-52.md; sem objetos/commits de agenda em develop |
| 2 | AXF-57 — Preservar snapshot e overrides da aplicação contratual | dependente da agenda publicada (AXF-55) | sem objetos/commits de snapshot em develop |
| 3 | AXF-12 (2/N…) — esteira de sincronização | schema/base já mergeados (#75/#76); fatias seguintes aguardam spec | commits "AXF-12 (1/N)" |
| 4 | Meta/engenharia: EPIC-008 + US-106 (rastreabilidade nativa Issue→branch→PR) | dívida real (issues US-097…105 abertas sem vínculo); reduz atrito futuro | issues #30/#31 abertas |

## Ações sugeridas após confirmação

1. Confirmar no Jira a prioridade (AXF-55 vs AXF-12 2/N vs AXF-57).
2. Criar branch `feature/AXF-55-*` a partir de `develop` (44f6475) e seguir o fluxo do
   `docs/SALESFORCE_DELIVERY.md` (PR → validação DEV → merge em develop → deploy DEV).
3. Registrar o doc de implementação em `docs/implementation/AXF-55.md` no padrão dos existentes.
