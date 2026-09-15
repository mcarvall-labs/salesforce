# AXF-55 — Plano de prontidão e ordem de execução (definição recebida 2026-09-06)

> Status: **DEFINIÇÃO PROPOSTA — sem autorização de build**. Gates G1, G2, G6, G7, G9 abertos.
> Nada de schema/operationId/provider/tolerância/budget foi inventado aqui. Implementação futura
> somente em worktree + AXON_DEV com autorização; nenhuma operação em AXON_PROD.

## 1. Situação das predecessoras (verificado em `develop` @ 44f6475)

| Predecessora | Capacidade | Em develop? | Evidência |
|---|---|---|---|
| AXF-56 | Submeter e aprovar Registros de Trabalho (work records) | **SIM** | `AXF_OBJ_WorkRecord__c`, `ALT_CLS_WorkRecordService`, `AXF_CLS_WorkRecordTriggerHandler`, PR #74 ("AXF-51/52/53/54/56") |
| AXF-57 | Preservar snapshot e overrides da aplicação contratual | **NÃO** | 0 commits AXF-57 em develop; nenhuma classe/objeto de snapshot/override no source; branch local `feature/AXF-57-contract-snapshot-overrides` tem 5 commits pré-consolidação (conteúdo já absorvido pelo #74) e **não** contém implementação de snapshot |

## 2. Consequência para a AXF-55

A definição recebida é explícita: *"AXF-56 e AXF-57 precedem geração para não publicar horas não
aprovadas nem saídas sem snapshot"* e *"não executar dependente de código ainda não integrado"*.
Portanto **a AXF-55 (geração de prévia delta/publicação) NÃO pode ser implementada enquanto a AXF-57
não estiver integrada em `develop`**.

## 3. Ordem funcional consolidada (a seguir)

1. **AXF-56** — já integrada (#74). Nada a fazer.
2. **AXF-57** — snapshot e overrides da aplicação contratual: **PRÓXIMA a executar** (bloqueia AXF-55).
3. **AXF-55** — gerar prévia delta + publicar ocorrências com checkpoint/idempotência (objeto desta definição).

## 4. O que falta para destravar (depende de decisão/dados do dono do produto)

- **Definição/ACs oficiais da AXF-57** (Jira/Confluence — não acessíveis nesta sessão), nos mesmos
  moldes da AXF-55, com: identidade por ocorrência (G6), snapshot imutável antes de publicar,
  interação com overrides, e evidência/retenção (G7). Não inventar schema nem regras.
- **Fechamento/liberação dos gates** aplicáveis (G1 forma física, G2 acesso, G6 identidade/
  concorrência, G7 evidência/retenção, G9 plano aprovado antes do build).
- Autorização explícita para build em worktree + AXON_DEV.
- Higiene: descartar/arquivar a branch local redundante `feature/AXF-57-contract-snapshot-overrides`
  antes de criar a branch real da AXF-57.

## 5. Próximos passos propostos (após autorização + ACs)

1. Criar worktree dedicado (padrão `.worktrees/salesforce/...`) para AXF-57 a partir de `develop`.
2. Implementar AXF-57 (snapshot + overrides) com testes; abrir PR → validar/integrar em `develop`.
3. Retornar a esta branch `feature/AXF-55-contract-agenda` (rebasar sobre o novo `develop`) e então
   implementar a AXF-55 conforme esta definição (preview delta, confirmação humana, run com
   checkpoint/idempotência, complete-through, WCAG 2.2 AA, PT-BR/EN, CRUD/FLS/ownership/sharing).
