# AXF-13 — Pluggy external identity across reprocessing and reconnections

- **Jira:** https://axon-personal-finances.atlassian.net/browse/AXF-13 (Epic AXF-10)
- **Branch:** `feature/AXF-13-pluggy-external-identity`, synchronized with `reconciled/base` after AXF-11 was finalized (uses `AXF_OBJ_PluggyConnection__c`).
- **Gates:** G6 fase de definição fechada (30/08). Contrato regente: `ARCHITECTURE-SPINE.md`
  §"Fechamento G6"; `IMPLEMENTATION-CONTRACTS.md` (SourceIdentity/alias — versão simplificada
  do G6 prevalece); comentário Jira 10202 (30/08).
- **Predecessora:** AXF-7 (Done). Vem **antes** de AXF-12 e não depende dela.

> Não autoriza deploy em UAT/PROD, exclusão, nem acesso a produção. Migração física = design
> apenas; execução depende de G9 fase execução.

---

## 1. O que esta US entrega (e o que fica para as US que criam os objetos)

Na base greenfield (`reconciled/base` + AXF-11), o único objeto integrado que existe é
`AXF_OBJ_PluggyConnection__c`. Os objetos de fato (BankAccount, CreditCard, transações,
fatura, categoria, investimento, empréstimo) **ainda não existem** — cada um é criado pela
US que o consome (AXF-12 sincroniza, AXF-84 descobre, AXF-14/15 CSV, cluster de cartões).

AXF-13 entrega o **contrato de identidade + os primitivos reutilizáveis + o mecanismo de
equivalência de reconexão**, provado a partir de base sem registros. As US que criam cada
objeto de fato aplicam este contrato ao adicionar `AXF_<ACR>_EXI_PluggyTransactionId__c` +
`AXF_<ACR>_EXI_FallbackKey__c` + `AXF_<ACR>_TXT_NormalizedDescription__c`.

| Entrega                                            | Componente                                                                                                                                                                                                                                                       |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Framing canônico (length-prefixed UTF-8) + SHA-256 | `AXF_CLS_IdentityFraming` (`frame` / `sha256Hex` / `key`) — puro, determinístico                                                                                                                                                                                 |
| Normalização de descrição versionada (D-62)        | `AXF_CLS_TextNormalization` (`normalize` + `POLICY_VERSION = norm-v1`)                                                                                                                                                                                           |
| Identidade do fato (primária vs. fallback)         | `AXF_CLS_PluggyFactIdentity` — `fromProviderId` (UUID verbatim) / `fallback(parentExternalId, bookingDate, signedAmount, description)` = `sha256(frame('fbk-v1', parent, ISO date, amount(2), norm-version, normalized desc))`; o ID do pai entra no hash (D-61) |
| Equivalência de reconexão (AC4/AC5)                | `AXF_OBJ_SourceEquivalence__c` + `AXF_CLS_SourceEquivalenceService` (`record` → PENDING; `verify` / `reject` gated por `AXF_CanConfigure`; `resolveStableConnection`)                                                                                            |
| Acesso negado sem revelar existência (AC7)         | consultas `WITH USER_MODE` + OWD Private; "não encontrada" para acesso ausente e miss genuíno                                                                                                                                                                    |

### Fora de escopo desta US

- Matching de conciliação, sugestão inteligente de duplicidade (Deferred).
- Migração física da identidade (AC6) = **design apenas**, ver §4; execução = G9.
- Campos de identidade nos objetos de transação/conta/cartão = entregues por AXF-12/84.
- Contrato de identidade manual/CSV = AXF-15.

---

## 2. Contrato de identidade (para AXF-12 / AXF-84 / cluster de cartões seguirem)

Por objeto de fato (`CCT`, `BAT`, `FTX`, `CCI`, …):

1. `AXF_<ACR>_EXI_PluggyTransactionId__c` — Text(255), `unique`, `externalId`,
   `caseSensitive=false` (UUID). **NÃO** `required` — ver regra (2). Chave de upsert quando
   a Pluggy fornece o id.
2. `AXF_<ACR>_EXI_FallbackKey__c` — Text(64), `unique`, `externalId`, **`caseSensitive=true`**.
   Valor de `AXF_CLS_PluggyFactIdentity.fallback(...)`. Usado quando não há id do provedor
   (manual/CSV/conector sem id).
3. **Validation Rule:** exatamente um de (1)/(2) preenchido.
4. `AXF_<ACR>_TXT_Description__c` (original, imutável) **+** `AXF_<ACR>_TXT_NormalizedDescription__c`
   (persistida, `AXF_CLS_TextNormalization.normalize`). Recalcular só por reprocesso
   versionado explícito.
5. Upsert idempotente pela External ID aplicável. Replay/concorrência → mesmo registro,
   `Version` + idempotency key, `CONFLICT` na divergência, `RESULT_UNKNOWN` no timeout
   (G6-7). Nada de `CommandExecution` universal.

## 3. Inventário dos 9 tipos + achados no `develop` legado (AC1)

| Tipo                         | ID do provedor                                                                                                                                        | Escopo de unicidade                                                                     | Achado / ação                                                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Conexão (`PluggyConnection`) | `AXF_CON_EXI_PluggyItemId__c` (operação) + `AXF_CON_TXT_ObservedItemId__c` (observado)                                                                | global (Item ID)                                                                        | **entregue por AXF-11.** Identidade validada por `GET /items/<id>`, não pelo ID (D-85).                                                                                                                                                                                                                                                               |
| Transação bancária (`BAT`)   | `AXF_BAT_EXI_PluggyTransactionId__c` (legado)                                                                                                         | Text(255) `unique` **global**, `externalId`, `caseSensitive=false`, **`required=true`** | UUID → global OK. **Achado:** `required=true` conflita com a regra "exatamente um de id/fallback" — deve virar não-`required` + Validation Rule quando AXF-12 criar o objeto. Sem `FallbackKey` / `NormalizedDescription` no legado.                                                                                                                  |
| Transação de cartão (`CCT`)  | `AXF_CCT_EXI_PluggyTransactionId__c` (legado)                                                                                                         | idem BAT                                                                                | idem BAT.                                                                                                                                                                                                                                                                                                                                             |
| Fatura (`CCI`)               | `AXF_CCI_EXI_PluggyInvoiceId__c` (opcional, `unique`, `externalId`) **+** `AXF_CCI_EXT_ExternalId__c` (`{LastFourDigits}_{YYYY-MM}`, `unique` global) | —                                                                                       | **Achado crítico (D-61 / G6-1):** `AXF_CCI_EXT_ExternalId__c` usa os 4 últimos dígitos — **não únicos** entre cartões/bancos → colisão. Deve passar a `{CreditCardExternalId}_{YYYY-MM}` (ou incluir banco + 4 dígitos) **antes** de qualquer build que dependa dele para associação fatura↔transação. `PluggyInvoiceId` permanece a chave preferida. |
| Conta bancária / Cartão      | `AXF_BA_EXI_*` / `AXF_CC_EXI_*` (a confirmar quando o objeto for criado)                                                                              | —                                                                                       | objeto criado por AXF-84/86; aplicar o contrato §2.                                                                                                                                                                                                                                                                                                   |
| Categoria                    | id da Pluggy                                                                                                                                          | global                                                                                  | sugestão (`LKP_Category__c`); usuário reclassifica em `LKP_UserCategory__c` (G6-3).                                                                                                                                                                                                                                                                   |
| Investimento / Empréstimo    | fora do escopo do MVP (Fechamento G4-6)                                                                                                               | —                                                                                       | sem identidade nova nesta fase.                                                                                                                                                                                                                                                                                                                       |

> Achados registrados também no comentário Jira 10202 (pendência atribuída a esta US).
> Os itens `unique` global do legado **falham alto** em colisão (não mesclam silenciosamente) —
> comportamento aceitável, mas o CCI precisa da correção para não bloquear faturas legítimas.

## 4. Migração de esquema de identidade — design (AC6, execução = G9)

1. **Dual-read** `vN` / `vN+1`: enquanto `normalizationPolicyVersion` ou o framing mudam, o
   serviço de ingestão calcula as duas chaves e procura por ambas antes de decidir inserir.
2. **Backfill** em lote (Batch/Queueable encadeado, `keyset watermark`), grava a chave nova
   num campo paralelo, **sem** tocar a chave antiga.
3. **Prova** antes do cutover: contagem/soma por moeda idênticas; zero colisão na chave nova;
   zero órfão; relatório de colisão vazio.
4. **Tombstones**: identidades retiradas ficam registradas (não reutilizar o valor).
5. **Cutover recuperável**: trocar o campo `externalId` ativo só depois da prova aprovada;
   `rollback watermark` permite voltar. O formato anterior **não** é removido antes da prova.
6. Ordem: `metadata → backfill → parity → flag → observe → contract`. Depende de G1/G6/G9.

## 5. Testes

| Classe                                 | Cobre                                                                                                                                                                       |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_CLS_IdentityFramingTest`          | determinismo; ordem importa; injeção de delimitador inerte; `null` ≠ vazio; byte-length UTF-8; hex minúsculo 64                                                             |
| `AXF_CLS_TextNormalizationTest`        | case/diacríticos/pontuação; idempotência; blank → vazio; versão exposta                                                                                                     |
| `AXF_CLS_PluggyFactIdentityTest`       | id do provedor verbatim; replay estável; mesmo dado local + pai diferente ⇒ chave diferente; sinal/escala do valor; exige pai/data/valor; ISO date zero-padded              |
| `AXF_CLS_SourceEquivalenceServiceTest` | `record` PENDING e idempotente; `verify` gated + idempotente + resolve; um VERIFIED por escopo ⇒ `CONFLICT`; rejeitada não verifica; conexão inexistente negada sem revelar |

Post-restack validation used a check-only deployment against `AXON_DEV`; no persistent
feature-branch deployment was made. Validation job `0Afaj00000ipUqkCAE` passed with all
26 specified Apex tests green. Coverage was 94% for `AXF_CLS_IdentityFraming`, 97% for
`AXF_CLS_PluggyFactIdentity`, 97% for `AXF_CLS_TextNormalization`, and 99% for
`AXF_CLS_SourceEquivalenceService`.
