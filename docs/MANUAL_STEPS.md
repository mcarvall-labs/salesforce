# Registro de passos manuais

Fonte única dos passos que **não são metadado versionado** e precisam de mão humana
em cada org (`AXON_DEV`, `AXON_UAT`, `AXON_PROD`) ou no GitHub. Existe para dar
rastreabilidade (cada passo tem PR) e para que um agente confira se o passo foi
executado **antes** de dar a US por concluída.

Regras do projeto: `agent-docs/rules/project/16-status.md` (label `manual-step`,
promoção) e `17-completion-and-pr.md`.

## Como usar

### Quem escreve

- Toda US/Bug cujo PR tem "Deployment Steps" diferente de `None` **acrescenta uma
  linha** na tabela [Ordem de execução](#ordem-de-execução) no mesmo PR, e recebe a
  label Jira `manual-step`.
- US que é **só passo manual** (sem código) também abre PR: o PR edita este arquivo
  (nova linha ou marcação de execução). Esse PR é o rastro da US.
- A linha entra **na posição de execução correta** (depois de tudo de que depende,
  antes de quem depende dela), nunca no fim por conveniência. Renumere se preciso;
  a coluna _Depende de_ explica a ordem.
- Passo concluído: troque o estado do ambiente por `Feito (AAAA-MM-DD)` e aponte a
  evidência (comentário Jira com print/texto, ou link). Passo que mudou de forma
  fica com o histórico no Jira, não aqui.

### Quem confere (agentes)

Antes de mover uma US para `No UAT` ou `Em PROD`, e antes de aprovar o code review
de uma US `manual-step`:

1. Procure a chave da US na coluna _US_ de todas as linhas.
2. Para o ambiente de destino, toda linha dela e de suas dependências precisa estar
   `Feito (data)` com evidência registrada. `Pendente` ou `Não verificado` **bloqueia**
   a conclusão: reporte, não mova o status.
3. Linha ausente para uma US com label `manual-step` ou com "Deployment Steps"
   diferente de `None` é lacuna: pare e corrija o registro.
4. Confirme o estado real no org/GitHub quando possível; o registro afirma, a
   conferência prova.

Estados: `Feito (data)` · `Pendente` · `Não verificado` (executado ou não, sem prova
no Jira/PRs; tratar como pendente) · `n/a` (não se aplica ao ambiente).

## Ordem de execução

Fase: **Pré** = antes do deploy do PR; **Pós** = depois do deploy; **Externo** =
fora de org Salesforce. Os passos 3, 4 e 5 só valem depois que a US indicada em
_Depende de_ estiver implantada no org.

| #   | US                     | Fase    | Passo (resumo)                                                                                           | Depende de         | DEV                           | UAT                                  | PROD           |
| --- | ---------------------- | ------- | -------------------------------------------------------------------------------------------------------- | ------------------ | ----------------------------- | ------------------------------------ | -------------- |
| 1   | EP01 (E1-2)            | Pré     | [Habilitar Person Account](#1-habilitar-person-account)                                                  | —                  | Feito (antes de 30/09)        | Não verificado                       | Não verificado |
| 2   | AXF-175                | Pós     | [Conferir OWD e hierarquia de papéis](#2-conferir-owd-e-hierarquia-de-papéis)                            | 1                  | Não verificado                | Não verificado                       | Pendente       |
| 3   | AXF-174                | Pós     | [Atribuir PSG, papel e dono aos 2 usuários](#3-atribuir-psg-papel-e-dono-aos-2-usuários)                 | AXF-246 implantada | Feito (2026-10-06)            | Feito (2026-10-06)                   | Pendente       |
| 4   | AXF-175                | Pós     | [Teste com 2 logins (isolamento de Titulares)](#4-teste-com-2-logins)                                    | 2, 3               | Não verificado                | Não verificado                       | Pendente       |
| 5   | AXF-179 / AXF-212      | Pós     | [Salvar Client Id/Secret do Pluggy](#5-salvar-client-idsecret-do-pluggy)                                 | 3                  | Não verificado                | Não verificado                       | Pendente       |
| 6   | AXF-185                | Pós     | [Conferir `AXF_CP_PluggySync` em quem sincroniza](#6-conferir-axf_cp_pluggysync)                         | 3                  | Não verificado                | Não verificado                       | Pendente       |
| 7   | AXF-196                | Pós     | [Conferir quem importa extrato](#7-conferir-quem-importa-extrato)                                        | 3                  | Não verificado                | Não verificado                       | Pendente       |
| 8   | AXF-184                | Pós     | [Agendar o sync diário (Anonymous Apex)](#8-agendar-o-sync-diário)                                       | 3, 5               | Não verificado                | Não verificado                       | Pendente       |
| 9   | AXF-161                | Pré     | [Remover o Flow `AXF_FLW_PluggyConnectionName`](#9-remover-o-flow-axf_flw_pluggyconnectionname)          | —                  | Feito (antes de 03/10)        | Não verificado                       | Pendente       |
| 10  | EP05 (E5-13)           | Pré     | [Ativar multimoeda](#10-ativar-multimoeda)                                                               | —                  | Feito (verificado 2026-10-07) | Feito (verificado 2026-10-07)        | Pendente       |
| 11  | EP05 (E5-13) / AXF-222 | Pós     | [Ativar EUR e USD em Gerenciar moedas](#11-ativar-eur-e-usd)                                             | 10                 | Feito (verificado 2026-10-07) | Feito, taxa do USD = 1 (placeholder) | Pendente       |
| 12  | PR #246                | Externo | [Check "Code review approved" como obrigatório em `develop`](#12-check-code-review-approved-obrigatório) | —                  | n/a                           | n/a                                  | n/a            |

Estado do passo 11 (GitHub): Feito (2026-10-07), confirmado pela API de branch
protection de `develop` (checks obrigatórios: `Lint and unit tests`,
`Validate Salesforce delta`, `Code review approved`). Rever se `uat` e `main`
precisam do mesmo.

Observações de estado (verificadas em 2026-10-07):

- **AXF-174** tem evidência no Jira (comentário de code review aprovado de 06/10,
  conferido nos dois orgs).
- **AXF-175** está em `No UAT` mas o Jira só tem o comentário de reprovação de 01/10;
  **não há evidência** dos passos 2 e 4. Registrar a evidência ou devolver ao
  `Backlog`.
- Passos 5 a 8 constam em PRs mergeados (#212, #253, #252, #259) como "a fazer", sem
  comentário de execução. Tratar como `Não verificado` até haver prova.
- PROD: nada foi promovido ainda; os passos viram obrigatórios na promoção para
  `main`.

## Detalhe dos passos

### 1. Habilitar Person Account

Configuração irreversível, não versionável (decisão E1-2). Em org novo, antes de
implantar os record types de Account (AXF-169). Setup > Configurações de conta >
habilitar contas pessoais. Já feito no DEV.
Evidência: print da configuração ou consulta `SELECT Id FROM RecordType WHERE
SobjectType='Account' AND IsPersonType=true`.

### 2. Conferir OWD e hierarquia de papéis

US sem código (AXF-175). Em cada org:

1. Setup > Configurações de compartilhamento: _Conta_ = **Privado**, _Contato_ =
   **Controlado pelo pai**. Objetos Axon filhos de Account herdam o acesso
   (Master-Detail).
2. Setup > Funções: hierarquia `Axon - Gestor Financeiro` (topo) >
   `Axon - Participante`.

Evidência: comentário na AXF-175 com o resultado por org.

### 3. Atribuir PSG, papel e dono aos 2 usuários

US sem código (AXF-174). **Pré-requisito:** AXF-246 (PSGs) e AXF-169 a AXF-173
implantadas no org. Atribuir ao **grupo**, não aos Permission Sets.

| Usuário               | Perfil               | Papel                      | PSG                        |
| --------------------- | -------------------- | -------------------------- | -------------------------- |
| Michel Carvalho Lopes | System Administrator | `Axon - Gestor Financeiro` | `AXF_PSG_GestorFinanceiro` |
| Gisele Lopes          | Standard User        | `Axon - Participante`      | `AXF_PSG_Participante`     |

Usernames: DEV `michel.carvalho.lopes@axon.com.dev` e `gisele.lopes@axon.com.dev`;
UAT `michel.lopes@axon.com.uat` e `giselepsicologaoficial@axon.com.dev`.

1. Setup > Usuários > Grupos de conjuntos de permissões (em cada usuário >
   _Atribuições de grupo de conjunto de permissões_): atribuir o PSG da tabela. Não
   atribuir PS individuais (`Axon - Usuário`, `Axon - Importar extrato`,
   `Axon - Configuração`, `Axon - Configuração (credenciais)`): já vêm nos grupos.
   Os dois grupos precisam estar com status _Atualizado_.
2. Conferir o campo _Função_ de cada usuário.
3. Dono dos registros: cada Titular (Account) com _Proprietário_ correto (Titulares
   de Michel → Michel; da Gisele → Gisele). Account > _Alterar proprietário_.
4. Teste por login: Gisele vê o app **Axon** e só os Titulares dela, não vê o app
   Axon – Configuração nem credenciais do Pluggy; Michel vê todos os Titulares e,
   pelo PSG, Configuração e credenciais; Cliente e Família não aparecem nas list
   views _Pessoas físicas_/_Empresas_.
5. Evidência (print ou texto) em comentário na AXF-174, separando DEV e UAT.

### 4. Teste com 2 logins

US sem código (AXF-175), depende dos passos 2 e 3.

- Login como Gisele: na tab Titulares, só as Accounts de que é proprietária.
- Login como Michel: as dele e as da Gisele (herança pela hierarquia).
- Se falhar: conferir proprietário da Account e que `Axon - Usuário` não tem
  _Ver todos_ em Account (não tem).

Evidência: comentário na AXF-175 com o resultado por org.

### 5. Salvar Client Id/Secret do Pluggy

Os segredos não fazem parte do deploy. Como administrador (PSG Gestor, que inclui
`AXF_PS_ConfiguracaoCredenciais`), abrir o Assistente de configuração e salvar
Client Id/Secret no passo 1. A atribuição de `AXF_PS_Configuracao` e
`AXF_PS_ConfiguracaoCredenciais` pedida no PR #212 foi **substituída** pelos PSGs do
passo 3 (decisão E1-6, 03/10): não atribuir PS individuais.

Evidência: print do passo 1 do assistente concluído (sem expor o segredo).

### 6. Conferir `AXF_CP_PluggySync`

Quem roda a sincronização do Pluggy precisa da custom permission `AXF_CP_PluggySync`,
concedida por `AXF_PS_Configuracao` (dentro do PSG Gestor). Sem ela, a regra de
validação bloqueia a gravação de contas e cartões Pluggy (AXF-185). Cumprido pelo
passo 3; conferir que o usuário que sincroniza está no PSG Gestor.

### 7. Conferir quem importa extrato

`AXF_PS_ImportarExtrato` (AXF-196) vem dentro dos dois PSGs (Participante e Gestor).
Cumprido pelo passo 3; conferir que quem importa OFX/CSV está num dos grupos.

### 8. Agendar o sync diário

Uma vez por org, como usuário com `AXF_CP_PluggySync` (PSG Gestor), executar o
Anonymous Apex:

```apex
ALT_CLS_PluggySyncSchedule.scheduleDaily();
```

É seguro repetir (substitui o job existente). Evidência: Setup > Jobs agendados com o
job do sync, ou o resultado da execução no comentário da AXF-184.

### 9. Remover o Flow `AXF_FLW_PluggyConnectionName`

AXF-161. O delete vai em `manifest/destructiveChangesPost.xml`. **Antes do deploy**
em cada org, o Flow precisa estar inativo/removível: no DEV a versão foi desativada
(_Obsolete_); no UAT o Flow existe como Draft (v1) e a validação falha com
`insufficient access rights on cross-reference id` até ele ser apagado à mão.
Depois de aplicado em **todos** os ambientes, esvaziar
`manifest/destructiveChangesPost.xml` e atualizar `docs/destructive-backlog.md`.
Esta chave não existe no Jira: criar/confirmar a US antes de dar o item por fechado.

### 10. Ativar multimoeda

Irreversível. Sem ela o campo `CurrencyIsoCode` e o objeto `CurrencyType` não
existem (conferido em PROD em 2026-10-07: `CurrencyType` não suportado). Setup >
Gerenciar moedas > _Ativar_ (moeda corporativa **BRL**). Fazer **antes** do deploy
de qualquer metadado que dependa de `CurrencyIsoCode` (contrato, Lançamento,
Transação do Cartão, EP-05 a EP-07). DEV e UAT já estão ativos.
Evidência: `SELECT IsoCode, IsActive, IsCorporate FROM CurrencyType`.

### 11. Ativar EUR e USD

AXF-222 (EP05-H18). Setup > Gerenciar moedas: moedas ativas **BRL** (corporativa),
**EUR** e **USD**, e nenhuma outra (EP-06). Necessário para compras em USD no cartão
(E6-11) e para o serviço de taxa cobrir EUR e USD (E5-13). Verificado em
2026-10-07: DEV tem BRL/EUR/USD ativas; UAT também, mas com taxa do USD = 1
(placeholder, o serviço da taxa EP05-H15 deve sobrescrever); PROD sem multimoeda.

### 12. Check "Code review approved" obrigatório

Concluído: ver estado acima. Se for criada outra branch de integração, repetir em
Settings > Branches.

## Analisado e não necessário

Verificado em 2026-10-07 (consulta aos orgs e a `force-app`/definição EP-01 a EP-07):

- **Contatos para várias contas** (`AccountContactRelation`) e **Equipes de contas**
  (`AccountTeamMember`): não aparecem em nenhum metadado versionado nem na definição.
  Eram do modelo legado (AXF-83, acesso por ACR + Account Team + objeto próprio),
  substituído por OWD Privado, hierarquia de papéis e Master-Detail com Account
  (EP-01 E1-4). DEV e UAT têm 0 registros nas duas; em PROD só `AccountContactRelation`
  existe (0 registros) e Equipes de contas não está ativa. **Não ativar** em nenhum org.

## Fora de escopo deste registro

Passos de PRs da linhagem anterior à redefinição de 30/09 (jobs de reposição,
renomear instituição "Caixa" etc., PRs #164 a #180) pertencem ao baseline legado
parqueado e não foram portados. Reabrir se esse código voltar a ser entregue.
