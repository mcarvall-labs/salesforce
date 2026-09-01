# AXF-84 — Descobrir contas e cartões autorizados na aplicação Pluggy

- **Jira:** https://axon-personal-finances.atlassian.net/browse/AXF-84 (Epic AXF-10)
- **Branch:** `feature/AXF-84-pluggy-source-discovery` — **empilhada sobre** `feature/AXF-13-pluggy-external-identity` (que por sua vez está sobre `feature/AXF-11-...`). Merge #44 → #45 → esta.
- **Gates:** G1/G2/G4/G5/G6/G7 fase de definição fechada. Contrato: `ARCHITECTURE-SPINE.md` §"Fechamento G5"; comentários Jira 10117 (Item ID da aplicação), 10164 (D-39/40/79/85), 10203 (G5).
- **Predecessoras:** AXF-11 (credenciais/consentimento/pausa), AXF-13 (identidade externa).

> Não importa histórico, não escolhe titular, não declara saldo final. Sem deploy em UAT/PROD.

---

## O que entrega

| Área                                      | Componente                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Autoridade durável por (conexão, produto) | `AXF_OBJ_IntegrationRun__c` (INR) — estado, cursor (página), watermark, tentativa, token de execução ativo único, `RunKey` = `sha256(frame('inr-v1', connectionId, 'ACCOUNTS'))` (uma execução por conexão+produto; replay reutiliza)                                                                                                                                                                                |
| Catálogo descoberto                       | `AXF_OBJ_BankAccount__c` (BA) + `AXF_OBJ_CreditCard__c` (CC) — OWD Private; `AXF_<>_EXI_PluggyAccountId__c` (chave de upsert, AXF-13); `AXF_<>_PKL_AvailabilityState__c` **CUSTODY** por padrão (AC3/G5-5); moeda/saldo/limite **originais** conforme a API; número/últimos-4 **mascarados** (AC6)                                                                                                                   |
| Cliente de descoberta                     | `AXF_CLS_PluggyDiscoveryService.startOrResume(connectionId)` — gate (`AXF_CLS_PluggyCollectionControlService.assertCollectionAllowed`), `GET /items/<id>` + `GET /accounts?itemId=<id>&page=N` paginado (até 10 páginas/execução), upsert BA/CC por external id via `AXF_CLS_PluggyFactIdentity.fromProviderId`, revalidação de consentimento (`AXF_CLS_PluggyConsentService`) ao final; `status()` e `discovered()` |
| Controller / LWC                          | `AXF_CLS_CTRL_SourceDiscovery` + `aXF_LWC_sourceDiscovery` — botão descobrir/continuar, tabela com situação real por fonte, mensagem "Nenhuma conta ou cartão…" (AC4), aviso de catálogo incompleto (AC5); WCAG (role status/alert/note, aria-live)                                                                                                                                                                  |
| Acesso                                    | `AXF_PS_PluggyIntegration` (serviço) + `AXF_PS_GestorFinanceiro` (configurador) recebem CRUD nos 3 objetos + as classes + tab; `AXF_CanConfigure` no servidor (AC6)                                                                                                                                                                                                                                                  |

## ACs → implementação

- **AC1** — usa só `AXF_CON_EXI_PluggyItemId__c` da conexão (Item ID da aplicação) + credenciais dessa aplicação. Sem link MeuPluggy, sem `GET /items` global. Autenticar ≠ descoberta.
- **AC2** — identidade/origem/moeda/associações **conforme a API**, via AXF-13. Upsert por external id → replay não duplica (teste `discoveryIsReplaySafe`). Sem registro manual (isso é AXF-86).
- **AC3** — BA/CC entram `AvailabilityState = CUSTODY`, lookup de titular vazio; nome/CPF/instituição não atribuem ninguém. Disponibilização = AXF-85.
- **AC4** — processadas as conexões sem fontes → `SUCCEEDED` + "Nenhuma conta ou cartão encontrado nas conexões informadas". Zero ≠ erro/parcial/sem-autorização (estados distintos: `FAILED_TERMINAL` para 401/403, `RESULT_UNKNOWN` para timeout).
- **AC5** — mais páginas que o limite → `FAILED_RETRYABLE` + cursor (botão "Continuar"); consentimento caiu durante a descoberta → `FAILED_TERMINAL` + "catálogo incompleto"; token de execução ativo único + `RunKey` idempotente (G5-4). Catálogo parcial **nunca** é apresentado como completo.
- **AC6** — `AXF_CanConfigure` no servidor; erro sanitizado sem nome/número/existência; números mascarados; segredos nunca nas respostas.
- **AC7** — `discovered()` retorna quantidade + situação real por fonte; permite retentativa segura. Sem histórico, sem titular, sem saldo final.

## Fora de escopo

Sincronização completa de transações (AXF-12), atribuição de titular (AXF-85), cadastros manuais (AXF-86), tutorial (AXF-89). Importação de histórico roda em background depois (D-40).

## Notas de revisão

1. **Ordenação reads → callouts → DML** no serviço para não bloquear callout por trabalho não commitado. A revalidação de consentimento (que faz callout + DML) é o primeiro DML, após todos os GETs da descoberta.
2. **`AXF_CLS_PluggyHttpCalloutMock`** (util de teste da AXF-11) ganhou o roteamento de `/accounts` — edição aditiva num util compartilhado.
3. **`AXF_BA/CC_LKP_Account__c` fica nulável** nesta US; AXF-85 promove a required + Restrict com backfill (G1/G9).
4. **Concorrência**: janela pequena entre o read-check (RUNNING + watermark < 15 min → CONFLICT) e o write do estado RUNNING; o `Version` + `RunKey` unique no upsert final é a garantia forte. Em uso real cada invocação é uma transação Aura separada.
5. **Paginação > 10 páginas**: hoje deixa `FAILED_RETRYABLE` + cursor para re-invocação manual pela tela; um Queueable encadeado é refinamento pós-MVP (ou entra com AXF-12).

## Validação

**12 testes Apex (100%) + 7 Jest (100%)** para AXF-84; suíte Pluggy completa (AXF-11+13+84) = **101 Apex + 30 Jest, 100% verdes**. Cobertura 85% (service) / 96% (controller). Deploy `NoTestRun` em AXON_DEV.
