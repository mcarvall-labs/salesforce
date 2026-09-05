# AXF-19 — Criar um Lançamento financeiro por wizard guiado

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-19
- Branch: `feature/AXF-19-entry-wizard`
- Base: `reconciled/base`
- Predecessoras: AXF-3 (contexto autorizado), AXF-86 (contas/cartões manuais) — ambas em `reconciled/base`.

> Sem deploy em UAT/PROD. Testes com dados fictícios.

## Decisões de contrato tomadas na abertura desta US

A própria Jira (comentário "Fechamento de gates — 30/08") deixa uma decisão para ser fechada
"na abertura desta US": qual contrato de dinheiro/mutação seguir, já que o `IMPLEMENTATION-CONTRACTS.md`
original (27/08) cita mecanismos retirados (`Household`, `AXF_OBJ_CommandExecution__c`,
`AllocationSet`, `BootstrapAuthority`). Conferi o `RECONCILIATION-CONTRACT.md` (linha 122/124):

- **Mantido:** IC §1 "Dinheiro e conservação" — `Money = { magnitude ≥ 0, direction, currency }`,
  arredondamento `HALF_UP`, valor/moeda original nunca reescritos.
- **Suspenso/bloqueado por G1/G2/G5/G6:** o envelope de mutação do IC §4/§9 (Household,
  `CommandExecution`, `AllocationSet`).
- **Substituto já fechado:** G6-7 (`ARCHITECTURE-SPINE.md`) — "Toda mutação material carrega
  `Version` esperada + idempotency key; divergência → `CONFLICT`... Sem `CommandExecution`
  universal."

**Implementação:** usei a álgebra de dinheiro mantida (magnitude/direção/moeda como campos
próprios, não `Currency` nativo — a org não usa multi-moeda nativa, mesma linha da AXF-87) e o
envelope G6-7 substituto (chave de idempotência gerada pelo cliente uma vez por confirmação +
`Version`), sem reintroduzir `CommandExecution`/Household. Se essa leitura não for a pretendida,
os dois pontos (tipo de dinheiro, chave de idempotência) são o que precisa mudar — o resto
(schema FTX, wizard, autorização) não depende dela.

## Escopo entregue

| Área                      | Componente                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Schema (G1-3, greenfield) | `AXF_OBJ_FinancialTransaction__c` (FTX) — titular required+Restrict, conta/cartão opcionais SetNull, `Direction` (DEBIT\|CREDIT), `Magnitude` (Number, não Currency), `CurrencyIsoCode`, `PurchaseDate`/`DueDate` (`Date`), `Status` (só `CONFIRMED` nesta US — lifecycle `ACTUAL_ONLY`), `Version`, `ClientRequestId` (chave de idempotência, unique/externalId) |
| Serviço                   | `AXF_CLS_FinancialEntryService` — autoridade (contexto autorizado AXF-3), validação, replay idempotente (mesma chave+payload → `ALREADY`; chave igual+payload diferente → `CONFLICT`), origem (conta/cartão) restrita a `AVAILABLE` do mesmo titular (G5-5)                                                                                                       |
| Controller                | `AXF_CLS_CTRL_FinancialEntry` — thin, erros sanitizados                                                                                                                                                                                                                                                                                                           |
| UI                        | `aXF_LWC_entryWizard` — 4 etapas (Contexto/Detalhes/Origem/Revisão), progresso, Voltar/Próxima, revisão final, nada persiste antes da confirmação                                                                                                                                                                                                                 |
| Acesso                    | `AXF_PS_FinancialEntry` (Create/Edit/Read em FTX, sem Delete) — adicionado aos PSGs Gestor **e** Participante (qualquer usuário Axon lança seu próprio evento); `AXF_CanConfigure` **não** é usado aqui — é entrada de dado comum, autorização é `WITH USER_MODE`/`as user` + contexto autorizado                                                                 |

## Fora de escopo (recortes próprios)

- Categoria (`AXF_FTX_LKP_Category__c`) — objeto de categoria ainda não existe no greenfield; entra quando essa capacidade for construída.
- Parcelas/recorrência/financiamento (`AXF_OBJ_InstallmentGroup__c`, `PKL_RecurringType`, etc.) — AXF-20.
- Vínculo com o fato de origem importado (`AXF_FTX_LKP_BankAccountTransaction__c`/`CreditCardTransaction__c`) e conciliação — depende de AXF-12 (BAT/CCT ainda não existem) e da própria conciliação (AXF-29/30/31).
- Estados de previsão (`IsEstimated=true`, `Certainty`) — reservado; esta US só cria lançamento confirmado à vista.
- Edição/exclusão de um lançamento existente — esta US é só criação; `Version`/lock otimista fica pronto para quando a edição vier.

## Segurança

- `AXF_FTX_LKP_Account__c` só aceita um Id presente em `AXF_CLS_AuthorizedContextService.listAuthorizedContexts()` do usuário corrente — nunca confia no `accountId` do cliente.
- Conta bancária/cartão informados são revalidados no servidor: precisam pertencer ao mesmo titular **e** estar `AVAILABLE` (nunca `CUSTODY`, G5-5).
- CRUD/FLS/sharing nativos (`WITH USER_MODE` / `insert as user`); sem `Delete` nesta US.
- Erros de autorização são neutros (não confirmam nem negam a existência do registro para quem não tem acesso).

## Validação

- Jest: suíte completa do worktree **94/94** (novo `aXF_LWC_entryWizard` 5/5).
- Apex: `AXF_CLS_FinancialEntryServiceTest` **9/9** no AXON_DEV — autorização, validação (magnitude, XOR conta/cartão, origem `CUSTODY` rejeitada), criação, replay idempotente, conflito por payload divergente, filtro de origens disponíveis.
- ESLint + Prettier limpos. Deploy `NoTestRun` em AXON_DEV, sem operação em AXON_PROD.
