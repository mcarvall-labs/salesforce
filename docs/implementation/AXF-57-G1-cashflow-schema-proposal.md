# G1 — Forma física do "CashFlow" contratual (proposta de schema)

> **Status: PROPOSTA — aguardando aprovação do dono do produto.**
> Não autoriza build, deploy ou operação em org. Fecha apenas a **forma física (G1)** para
> destravar AXF-55 (publicar a agenda) e AXF-57 (snapshot + overrides). G2 (acesso), G6
> (identidade/concorrência/resultado desconhecido) e G7 (evidência/retenção) continuam
> abertos e são citados só onde a forma física depende deles.
>
> Fontes lidas: AXF-52/53/54/55/56/57 (Jira), `docs/implementation/AXF-19.md` e `AXF-52.md`,
> objetos em `develop` @ `f2706dd` (`AXF_OBJ_Contract__c`, `AXF_OBJ_ContractTermVersion__c`,
> `AXF_OBJ_FinancialTransaction__c`, `AXF_OBJ_WorkRecord__c`), memória de reconciliação
> ("CashFlow → FinancialTransaction", decisão 29/08). Nada de schema/provider/tolerância
> inventado — onde falta decisão, está listado em §8.

---

## 1. Decisão central

**"CashFlow" não vira objeto novo. "CashFlow" é o `AXF_OBJ_FinancialTransaction__c` (FTX,
"Lançamento Financeiro")** — a mesma forma física já entregue na AXF-19, conforme a
reconciliação de nomes de 29/08 (`CashFlow → FinancialTransaction`).

O que a AXF-57 chama de distinção "**CashFlow** recebe snapshot / **FinancialEntry** não
recebe contrato/snapshot direto" traduz-se assim no alvo reconciliado:

| Vocabulário AXF-57                              | Forma física alvo                                                                                                                      |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| "CashFlow" (recebe snapshot 1:1)                | um **FTX gerado a partir de um contrato** (`AXF_FTX_PKL_Origin__c = CONTRACT`) que possui exatamente **um** registro filho de snapshot |
| "FinancialEntry" (sem contrato/snapshot direto) | um **FTX manual/importado** (`Origin = MANUAL                                                                                          | IMPORT`) — **zero** filhos de snapshot, **nenhum** campo de contrato no próprio FTX |

O contrato **nunca** é referenciado diretamente no FTX. A ligação é indireta e só existe
para ocorrências geradas:

```
FTX ──(master-detail 1:1)── ContractApplicationSnapshot ──(lookup)── ContractTermVersion ──(master-detail)── Contract
```

Assim um FTX manual permanece contrato-livre por construção (não é possível "vazar"
contrato para um lançamento manual), e "FinancialEntry não recebe contrato direto" é uma
**invariante de schema**, não uma regra de código.

### Objetos

| Objeto                                   | Prefixo | Novo?              | Papel                                                                                         |
| ---------------------------------------- | ------- | ------------------ | --------------------------------------------------------------------------------------------- |
| `AXF_OBJ_FinancialTransaction__c`        | FTX     | existe (AXF-19/20) | a ocorrência de fluxo de caixa. Recebe **deltas** (§3)                                        |
| `AXF_OBJ_ContractApplicationSnapshot__c` | CAS     | **novo**           | snapshot imutável 1:1 do termo aplicado a uma ocorrência gerada (§4)                          |
| `AXF_OBJ_ContractOccurrenceOverride__c`  | COV     | **novo**           | override manual de um valor da ocorrência; sobrevive à regeneração (§5)                       |
| `AXF_OBJ_ContractGenerationRun__c`       | CGR     | **novo**           | execução de geração da agenda de um contrato: concorrência, checkpoint, complete-through (§6) |

Nenhum objeto genérico de "snapshot de payload cru", `CommandExecution`, `AuditEvent`
obrigatório ou `AllocationSet` é criado (RECONCILIATION-CONTRACT; consistente com o
envelope G6-7 já usado na AXF-19).

---

## 2. `AXF_OBJ_FinancialTransaction__c` — estado atual (referência)

Campos já em `develop` (AXF-19 + AXF-20), preservados:

`AXF_FTX_LKP_Account__c` (required, Restrict) · `AXF_FTX_LKP_BankAccount__c` /
`AXF_FTX_LKP_CreditCard__c` (opcionais, SetNull) · `AXF_FTX_PKL_Direction__c`
(DEBIT|CREDIT) · `AXF_FTX_NUM_Magnitude__c` (Number 18,2, positivo) ·
`AXF_FTX_TXT_CurrencyIsoCode__c` · `AXF_FTX_DAT_PurchaseDate__c` /
`AXF_FTX_DAT_DueDate__c` · `AXF_FTX_PKL_Status__c` (**hoje** CONFIRMED|PLANNED) ·
`AXF_FTX_PKL_Modality__c` (RECURRING|INSTALLMENT|PRICE|SAC) · `AXF_FTX_NUM_Sequence__c` ·
`AXF_FTX_TXT_ScheduleGroupKey__c` (agrupa ocorrências de um cronograma, **não única**) ·
`AXF_FTX_EXI_ClientRequestId__c` (UUID do cliente, unique/externalId — envelope G6-7) ·
`AXF_FTX_NUM_Version__c` · `AXF_FTX_NUM_PrincipalPortion__c` / `InterestPortion__c` /
`FeePortion__c` / `ClosingBalance__c` · `AXF_FTX_CHK_IsEstimated__c` /
`RoundingResidual__c`. Sharing `Private`.

---

## 3. `AXF_OBJ_FinancialTransaction__c` — deltas propostos

| Campo                                    | Tipo                                                                    | Regras                                                            | Motivo                                                                                                                                                                                                                                                                                              |
| ---------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_FTX_PKL_Origin__c`                  | Picklist restrita `MANUAL` \| `IMPORT` \| `CONTRACT`                    | required; default `MANUAL`; **imutável após create**              | separa "CashFlow contratual" de "FinancialEntry" na forma física. `IMPORT` reservado para o casamento futuro AXF-16/28 (BAT/CCT → FTX) — declarado agora para não migrar depois                                                                                                                     |
| `AXF_FTX_EXI_OccurrenceKey__c`           | Text 64, Unique, External Id, caseSensitive                             | preenchido **só** quando `Origin = CONTRACT`; nulo caso contrário | **identidade determinística por ocorrência** (G6). `sha256Hex(frame('ftx-occ-v1', contractKey, termKey, periodIndex))` via `AXF_CLS_IdentityFraming`. Regeração faz `upsert` por esta chave → casa ocorrências existentes em vez de duplicar. Distinta do `ClientRequestId` (UUID do wizard manual) |
| `AXF_FTX_PKL_Status__c`                  | **acrescentar** valores `DRAFT`, `SUPERSEDED`, `REALIZED`, `RECONCILED` | ver máquina de estado §5.2                                        | AXF-55 distingue "drafts gerados e não alterados" (regeneráveis) de "confirmados, realizados, conciliados" (intocáveis) e de "superseded". `PLANNED` mantido para lançamentos manuais futuros; `CONFIRMED` mantido                                                                                  |
| `AXF_FTX_LKP_SupersededByTransaction__c` | Lookup(FTX), SetNull                                                    | preenchido quando `Status = SUPERSEDED`                           | rastreia a ocorrência que substituiu esta numa regeneração; preserva a anterior reproduzível                                                                                                                                                                                                        |
| `AXF_FTX_DT_GeneratedAt__c`              | DateTime                                                                | preenchido só p/ `Origin = CONTRACT`                              | quando a ocorrência foi materializada pela última geração                                                                                                                                                                                                                                           |
| `AXF_FTX_LKP_GenerationRun__c`           | Lookup(`AXF_OBJ_ContractGenerationRun__c`), SetNull                     | a última execução que criou/atualizou esta ocorrência             | rastreabilidade run → ocorrências                                                                                                                                                                                                                                                                   |

Notas:

- **Nenhum** campo de `Contract`/`TermVersion` no FTX — invariante do §1.
- `Origin` imutável: uma vez `CONTRACT`, o registro não pode virar `MANUAL` e vice-versa
  (validação de servidor + FLS de update negada no campo).
- Field History Tracking ligado em `Status`, `Magnitude`, `DueDate` (evidência nativa G7,
  proporcional — sem objeto de auditoria).

---

## 4. `AXF_OBJ_ContractApplicationSnapshot__c` (CAS) — snapshot imutável 1:1

**Sharing: `ControlledByParent`** (herda o FTX, que herda o `Account` titular).
**Relação: Master-Detail para FTX** (`AXF_CAS_MDR_Transaction__c`), com `reparentable = false`.
1:1 garantido por **um campo lookup único** no CAS para o FTX **e** uma regra de unicidade
(um FTX tem no máximo um CAS). Imutável: sem FLS de update em nenhum campo; `Status` do FTX
só transita, o CAS nunca é editado — uma nova geração **cria um novo FTX SUPERSEDED + novo
CAS**, nunca reescreve.

| Campo                                                   | Tipo                                                                   | Conteúdo congelado                                                                                                                                                                                                                                              |
| ------------------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_CAS_MDR_Transaction__c`                            | Master-Detail(FTX), unique                                             | a ocorrência (1:1)                                                                                                                                                                                                                                              |
| `AXF_CAS_LKP_TermVersion__c`                            | Lookup(`AXF_OBJ_ContractTermVersion__c`), Restrict                     | o termo aplicado                                                                                                                                                                                                                                                |
| `AXF_CAS_NUM_TermRevision__c`                           | Number 9,0                                                             | `AXF_CTV_NUM_Revision__c` no instante da geração                                                                                                                                                                                                                |
| `AXF_CAS_EXI_TermKey__c`                                | Text 80, External Id                                                   | `AXF_CTV_EXI_TermKey__c` (redundante e imutável mesmo se o termo for reparentado no futuro)                                                                                                                                                                     |
| `AXF_CAS_EXI_AppliedHash__c`                            | Text 64, External Id                                                   | `sha256Hex(frame(...))` de **todos** os insumos materiais aplicados (modelo, taxa, valor contratado, proporcionalidade, calendário, timezone, período, quantidade de horas/parcelas, índice). Prova de que a saída é reproduzível a partir do que foi congelado |
| `AXF_CAS_PKL_Provenance__c`                             | Picklist restrita `DEFAULTED` \| `OVERRIDDEN`                          | `DEFAULTED` = valores 100% do termo; `OVERRIDDEN` = ao menos um COV aplicado (§5)                                                                                                                                                                               |
| `AXF_CAS_PKL_RemunerationModel__c`                      | Picklist restrita `MONTHLY`\|`HOURLY`\|`FIXED`                         | cópia de `AXF_CTV_PKL_RemunerationModel__c`                                                                                                                                                                                                                     |
| `AXF_CAS_PKL_ProportionalityPolicy__c`                  | Picklist restrita `CALENDAR_DAYS`\|`BUSINESS_DAYS`\|`FIXED_30`\|`NONE` | cópia de `AXF_CTV_PKL_ProportionalityPolicy__c`                                                                                                                                                                                                                 |
| `AXF_CAS_TXT_CalendarPolicy__c`                         | Text 255                                                               | cópia de `AXF_CTV_TXT_CalendarPolicy__c`                                                                                                                                                                                                                        |
| `AXF_CAS_TXT_TimeZone__c`                               | Text 64                                                                | cópia de `AXF_CTV_TXT_TimeZone__c`                                                                                                                                                                                                                              |
| `AXF_CAS_CUR_ContractedAmount__c`                       | Number 18,2                                                            | cópia de `AXF_CTV_CUR_ContractedAmount__c`                                                                                                                                                                                                                      |
| `AXF_CAS_CUR_Rate__c`                                   | Number 18,6                                                            | cópia de `AXF_CTV_CUR_Rate__c`                                                                                                                                                                                                                                  |
| `AXF_CAS_NUM_HoursQuantity__c`                          | Number 18,2                                                            | cópia de `AXF_CTV_NUM_HoursQuantity__c` (quando `HOURLY`)                                                                                                                                                                                                       |
| `AXF_CAS_NUM_InstallmentIndex__c`                       | Number 9,0                                                             | posição desta ocorrência (1..n)                                                                                                                                                                                                                                 |
| `AXF_CAS_NUM_InstallmentTotal__c`                       | Number 9,0                                                             | `AXF_CTV_NUM_Installments__c`                                                                                                                                                                                                                                   |
| `AXF_CAS_DAT_PeriodFrom__c` / `AXF_CAS_DAT_PeriodTo__c` | Date                                                                   | o período de competência coberto pela ocorrência                                                                                                                                                                                                                |
| `AXF_CAS_TXT_CurrencyIsoCode__c`                        | Text 3                                                                 | moeda original congelada (nunca convertida)                                                                                                                                                                                                                     |
| `AXF_CAS_LKP_WorkRecord__c`                             | Lookup(`AXF_OBJ_WorkRecord__c`), SetNull                               | quando `HOURLY`: o(s) registro(s) de trabalho aprovado(s) que embasaram a quantidade (AXF-56). **Só work records `APPROVED`** — AC AXF-55 "não publicar horas não aprovadas"                                                                                    |
| `AXF_CAS_TXT_EngineVersion__c`                          | Text 40                                                                | versão do motor de cálculo/amortização (`AMORTIZATION-POLICY` vN) — evidência nativa não prova idempotência, mas fixa a política aplicada                                                                                                                       |
| `AXF_CAS_LKP_GenerationRun__c`                          | Lookup(CGR), SetNull                                                   | a execução que produziu este snapshot                                                                                                                                                                                                                           |
| `AXF_CAS_DT_CapturedAt__c`                              | DateTime                                                               | instante do congelamento                                                                                                                                                                                                                                        |

> **Regra de imutabilidade**: o CAS não tem permissão de `edit` em nenhuma PS. Uma
> validação de servidor rejeita qualquer `update`. Correção = novo FTX `SUPERSEDED` +
> novo CAS (via regeneração ou correção AXF-16). Isto satisfaz "snapshot imutável 1:1".

---

## 5. `AXF_OBJ_ContractOccurrenceOverride__c` (COV) — override manual

**Sharing: `ControlledByParent`** (herda o FTX). **Lookup para FTX** (não master-detail —
o override deve **sobreviver** mesmo que o FTX seja `SUPERSEDED`; ver §5.3).

| Campo                            | Tipo                                      | Regras                                                                                                                                                    |
| -------------------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_COV_LKP_Transaction__c`     | Lookup(FTX), Restrict                     | a ocorrência afetada (a **corrente**, não a superseded)                                                                                                   |
| `AXF_COV_EXI_OccurrenceKey__c`   | Text 64, External Id                      | **cópia** do `AXF_FTX_EXI_OccurrenceKey__c` — é a âncora estável do override através de regenerações (o FTX pode ser recriado; a occurrence key não muda) |
| `AXF_COV_PKL_Field__c`           | Picklist restrita                         | o campo sobrescrito: `MAGNITUDE` \| `DUE_DATE` \| `PERIOD_FROM` \| `PERIOD_TO` \| `DIRECTION` \| `SUPPRESSED` (ocorrência removida manualmente)           |
| `AXF_COV_TXT_DefaultValue__c`    | Text 255                                  | valor calculado pelo termo (string canônica)                                                                                                              |
| `AXF_COV_TXT_OverrideValue__c`   | Text 255                                  | valor humano (string canônica; nulo quando `Field = SUPPRESSED`)                                                                                          |
| `AXF_COV_TAL_Reason__c`          | Long Text Area                            | **obrigatório** (validação de servidor)                                                                                                                   |
| `AXF_COV_LKP_DecidedBy__c`       | Lookup(User), Restrict                    | ator                                                                                                                                                      |
| `AXF_COV_DT_DecidedAt__c`        | DateTime                                  | instante                                                                                                                                                  |
| `AXF_COV_PKL_State__c`           | Picklist restrita `ACTIVE` \| `WITHDRAWN` | um override pode ser retirado (volta ao default na próxima geração); nunca apagado                                                                        |
| `AXF_COV_NUM_Version__c`         | Number 9,0                                | concorrência otimista (envelope G6-7)                                                                                                                     |
| `AXF_COV_EXI_ClientRequestId__c` | Text 36, Unique, External Id              | idempotência da confirmação do override                                                                                                                   |

### 5.1 Um override por (ocorrência, campo)

Unicidade: `(AXF_COV_EXI_OccurrenceKey__c, AXF_COV_PKL_Field__c)` único **entre os
`ACTIVE`**. Trocar um override = `WITHDRAWN` no antigo + novo `ACTIVE` (histórico
preservado).

### 5.2 Máquina de estado do FTX (proposta)

```
                 geração
   (nada) ─────────────────────▶ DRAFT ──(confirmação humana da agenda)──▶ CONFIRMED
                                  │  ▲                                       │
              regeneração cria    │  │ regeneração NÃO toca                  │ realização (AXF-28+)
              nova ocorrência ────┘  │ (override / downstream)               ▼
              e marca esta:          │                                    REALIZED ──(conciliação AXF-30)──▶ RECONCILED
                    SUPERSEDED ──────┘
```

- **`DRAFT`**: gerada, ainda não confirmada pela revisão humana da agenda (AXF-55). **Único
  estado que a regeneração pode criar, atualizar ou marcar `SUPERSEDED`.**
- **`SUPERSEDED`**: substituída por uma ocorrência mais nova; preservada e reproduzível
  (`AXF_FTX_LKP_SupersededByTransaction__c`).
- **`CONFIRMED` / `REALIZED` / `RECONCILED`**: a regeneração **nunca** toca. Nem uma
  ocorrência `DRAFT` que tenha um COV `ACTIVE` (a regeneração recalcula o default e o
  mantém no snapshot, mas o valor efetivo do FTX continua o do override).
- `PLANNED` continua existindo para lançamentos manuais planejados (AXF-19 futuro), fora
  desta esteira.

### 5.3 Regeneração idempotente (preview de §AXF-55, forma física aqui)

1. Motor calcula as ocorrências do horizonte a partir do termo `ACTIVE`.
2. Para cada ocorrência calculada: `OccurrenceKey` determinística (§3).
3. Casa com FTX existente pela `OccurrenceKey`:
   - **não existe** → _adicionada_ (novo FTX `DRAFT` + CAS).
   - **existe `DRAFT` sem COV** e valores mudaram → _superseded_: novo FTX `DRAFT` + CAS,
     antigo → `SUPERSEDED`.
   - **existe `DRAFT` sem COV** e valores iguais → _preservada_ (nada muda; `AppliedHash`
     idêntico).
   - **existe com COV `ACTIVE`** → _preservada_; CAS recalculado só reflete o novo default,
     `Provenance = OVERRIDDEN`, valor efetivo intocado.
   - **existe `CONFIRMED`/`REALIZED`/`RECONCILED`** → _bloqueada_ (reportada no preview,
     nunca alterada).
4. Ocorrência que sumiu do cálculo e cujo FTX é `DRAFT` sem COV → `SUPERSEDED`.
5. Nada é escrito antes da confirmação humana (o preview é derivado, não persistido — ou
   persistido só no CGR como contagem/resumo; ver §8-Q4).

---

## 6. `AXF_OBJ_ContractGenerationRun__c` (CGR) — execução da geração

Espelha a forma do `AXF_OBJ_IntegrationRun__c` (autoridade durável por escopo), mas para
**geração de agenda contratual**, não para Pluggy.

| Campo                                                                    | Tipo                                                                                                                                                 | Papel                                                                                                                                |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `AXF_CGR_MDR_Contract__c`                                                | Master-Detail(`AXF_OBJ_Contract__c`)                                                                                                                 | escopo                                                                                                                               |
| `AXF_CGR_EXI_RunKey__c`                                                  | Text 64, Unique, External Id                                                                                                                         | `IdentityFraming.key(['cgr-v1', contractKey, horizonKey])`                                                                           |
| `AXF_CGR_PKL_State__c`                                                   | Picklist restrita `PENDING`\|`PREVIEWING`\|`AWAITING_CONFIRMATION`\|`APPLYING`\|`SUCCEEDED`\|`FAILED_RETRYABLE`\|`FAILED_TERMINAL`\|`RESULT_UNKNOWN` | máquina de estado (G6)                                                                                                               |
| `AXF_CGR_TXT_ActiveToken__c`                                             | Text 64, Unique                                                                                                                                      | mutex de execução: impede duas gerações ativas do mesmo contrato (AC AXF-55). Concorrente encontra a corrente e "oferece acompanhar" |
| `AXF_CGR_DAT_HorizonFrom__c` / `AXF_CGR_DAT_HorizonTo__c`                | Date                                                                                                                                                 | janela pedida                                                                                                                        |
| `AXF_CGR_DAT_CompleteThrough__c`                                         | Date                                                                                                                                                 | até onde o delta foi aplicado e verificado; nunca sobre intervalo incompleto                                                         |
| `AXF_CGR_NUM_Added__c` / `Superseded__c` / `Preserved__c` / `Blocked__c` | Number 9,0                                                                                                                                           | contadores do delta (preview e resultado)                                                                                            |
| `AXF_CGR_NUM_RoundingResidual__c`                                        | Number 18,2                                                                                                                                          | residual total do horizonte                                                                                                          |
| `AXF_CGR_NUM_Attempt__c` / `AXF_CGR_NUM_Version__c`                      | Number                                                                                                                                               | retomada / concorrência otimista                                                                                                     |
| `AXF_CGR_TXT_Cursor__c`                                                  | Text 255                                                                                                                                             | checkpoint de retomada (índice de ocorrência)                                                                                        |
| `AXF_CGR_LKP_ConfirmedBy__c` / `AXF_CGR_DT_ConfirmedAt__c`               | User / DateTime                                                                                                                                      | quem confirmou a publicação                                                                                                          |
| `AXF_CGR_TXT_Message__c`                                                 | Text 255                                                                                                                                             | causa sanitizada / próxima ação segura                                                                                               |
| `AXF_CGR_TXT_CorrelationId__c`                                           | Text 40                                                                                                                                              | rastreabilidade                                                                                                                      |

Sharing: `ControlledByParent` (Contract).

> **Alternativa considerada e recusada**: generalizar `AXF_OBJ_IntegrationRun__c` para os
> dois domínios. Recusada porque INR está acoplado a `AXF_INR_LKP_Connection__c` (Pluggy) e
> aos produtos `ACCOUNTS|CARDS|TRANSACTIONS|BILLS`; misturar geração contratual poluiria o
> contrato do sync. Um objeto por domínio, mesma **forma**.

---

## 7. Rastreabilidade até o recebimento (AC AXF-57 "percorre alocação → alvo de liquidação → fluxo → snapshot")

O caminho é navegável **sem atalho local**, todo por relações nativas:

```
Recebimento futuro (FX/liquidação, AXF-59..63)
  └─ alocação ──▶ FTX (a ocorrência)
                   └─ CAS (snapshot 1:1)
                        └─ TermVersion ──▶ Contract
```

A alocação e o "alvo de liquidação" são schema de AXF-59..63 (fora desta proposta); o que
esta proposta garante é que **a partir de qualquer FTX contratual existe exatamente um CAS
imutável** que reconstrói o termo, a revisão, o hash e a proveniência.

---

## 8. Decisões que ainda faltam ao dono do produto

| #      | Questão                                                                                                                                                                                                                                                                    | Recomendação                                                                                                                                                 |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Q1** | O CAS deve ser **Master-Detail** (herda sharing/immutability do FTX, sem owner próprio) ou **Lookup** (owner/sharing próprio)?                                                                                                                                             | **Master-Detail** — o snapshot não tem vida independente do lançamento; simplifica G2                                                                        |
| **Q2** | `OccurrenceKey` inclui `periodIndex` (posição) ou `periodFrom` (data de competência)? Se o calendário mudar entre gerações, um índice puro desloca tudo; uma data pode colidir se o modelo emitir duas ocorrências no mesmo dia.                                           | **`frame(contractKey, termKey, periodFrom, installmentIndex)`** — data + índice juntos; robusto a mudança de calendário e a duplicidade no mesmo dia         |
| **Q3** | Override por **campo** (COV com `PKL_Field`, granular) ou por **ocorrência inteira** (um COV congela o FTX todo)?                                                                                                                                                          | **Por campo** — AC pede "default, novo valor, motivo"; granular preserva melhor a regeneração dos campos não sobrescritos                                    |
| **Q4** | O **preview** do delta (AXF-55) é puramente derivado (calculado e descartado até a confirmação) ou persistido como linhas provisórias?                                                                                                                                     | **Derivado** — "nenhuma ocorrência é publicada antes da confirmação"; o CGR guarda só os **contadores** e o `AppliedHash` agregado para o replay idempotente |
| **Q5** | `Origin` no FTX: 3 valores (`MANUAL\|IMPORT\|CONTRACT`) agora, ou só `MANUAL\|CONTRACT` e `IMPORT` quando AXF-16/28 chegar?                                                                                                                                                | **3 agora** — declarar o enum completo evita um `Type change` de picklist restrita depois                                                                    |
| **Q6** | Field History Tracking em `AXF_FTX_*` é evidência G7 suficiente para "reproduzir o histórico após mudanças contratuais", ou o CAS precisa também de um `AXF_CAS_TAL_InputsJson__c` com o vetor de insumos serializado?                                                     | Decidir junto com **G7**. Recomendação mínima: `AppliedHash` + campos tipados no CAS bastam para reprodução; o JSON só se a auditoria exigir o vetor literal |
| **Q7** | `AXF_CTV_PKL_RemunerationModel__c` tem hoje `MONTHLY\|HOURLY\|FIXED`. A agenda de `FIXED` (marcos/parcelas) precisa de uma tabela de marcos no TermVersion que **não existe** (`AXF_CTV_NUM_Installments__c` dá só a contagem). Isso é schema de **AXF-54** ou entra aqui? | Provavelmente **AXF-54** (modelos de remuneração) — confirmar. Sem a tabela de marcos, `FIXED` só gera N parcelas iguais                                     |

---

## 9. O que esta proposta **não** faz

- Não cria objeto, campo, PS, aba ou automação em nenhuma org.
- Não fecha G2/G6/G7/G9 — só descreve a forma física de que eles dependem.
- Não implementa AXF-55 nem AXF-57 — o build começa só após aprovação desta forma +
  liberação dos demais gates + autorização explícita, em worktree + AXON_DEV.
- Não altera `AXF_OBJ_FinancialTransaction__c` já implantado — os deltas do §3 são a
  proposta a aprovar.
- Não toca AXON_UAT/AXON_PROD.

---

## 10. Se aprovado — ordem de execução

1. **G1 fechado** com esta forma (registrar "Fechamento G1 — CashFlow contratual" onde
   moram as seções de fechamento de gate).
2. PR de **schema** (fatia 1): `Origin`/`OccurrenceKey`/status novos no FTX + os 3 objetos
   novos (CAS, COV, CGR) vazios de automação, com FLS/sharing e testes de deploy.
3. **AXF-57** (fatia 2): motor de snapshot + fluxo de override, sobre o schema da fatia 1.
4. **AXF-55** (fatia 3): preview delta + run com checkpoint/idempotência, consumindo CAS +
   COV + CGR.
5. Rebase de `feature/AXF-55-contract-agenda` sobre o novo `develop`.
