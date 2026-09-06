# AXF-99 — Roteiro de captura da mídia do guia Pluggy

Guia: `aXF_LWC_pluggyGuide` · static resource: `AXF_pluggyGuideMedia` (5 pares `<base>.mp4` +
`<base>-poster.png`). Trocar só o static resource — **sem mudança de código** (a menos que um
fluxo do Pluggy tenha mudado e o `mediaAlt`/`body` de `labels.js` precise de ajuste).

## Auditoria da mídia atual (fase UX, a substituir)

| clip              | passo do guia                        | estado atual                                                                      | problema                                                                                                                                          |
| ----------------- | ------------------------------------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `meu-pluggy`      | conectar banco no MeuPluggy          | MeuPluggy "Data Passport" → Conexões → **Nova conexão**                           | OK — anonimizado (Inter/C6/Caixa/Sicoob). Confirmar UI atual.                                                                                     |
| `criar-aplicacao` | abrir/criar a aplicação no Dashboard | home do Dashboard, cursor em "Aplicações"                                         | **banner "Seu trial expirou"**; não mostra a aplicação sendo criada/selecionada; poster com clutter ("Solicitar Acesso à Produção", "Fazer tour") |
| `aplicacao`       | autorizar a conexão para a aplicação | app "Axon Exemplo" → Demo → ⋮                                                     | **"trial expirou"**; não mostra o fluxo Conectar Conta → Continuar → MeuPluggy → Conectar → escolher conexão                                      |
| `credenciais`     | copiar Client ID e Client Secret     | **poster idêntico ao de `criar-aplicacao`**                                       | **não mostra os campos Client ID / Client Secret**                                                                                                |
| `copiar-item-id`  | copiar o Item ID de cada conexão     | app → Demo → ⋮ → **Copiar Item ID** (Item ID fictício `0000…0002`, DEMO-001..004) | Melhor do conjunto. Confirmar UI atual; quase idêntico visualmente ao `aplicacao`                                                                 |

**Comum a corrigir:** eliminar qualquer banner "trial expirou / Trial Expirado", checklist
"Solicitar Acesso à Produção" e "Fazer tour" do enquadramento.

## Anonimização (obrigatória — AXF-89 AC5 / AXF-99)

- Pessoa: **"Ana"** (avatar "AS"). Nenhum nome real, foto, e-mail.
- Contas: **DEMO-001, DEMO-002, …**; saldos fictícios redondos (R$ 250, R$ 1.500…).
- Item ID exibido: **`0000000-0000-4000-8000-000000000002`** (nunca o Item ID real do Michel).
- Aplicação: **"Axon Exemplo"**.
- Bancos **podem** manter nome/logo reais (Inter, C6, Caixa, Nubank…).
- Client ID / Client Secret: **borrar** ou substituir por `axon-exemplo-client-id` /
  `••••••••••••` — nunca o valor real.
- Recortar só a área da UI: **sem barra do navegador**, sem abas, sem janela do gerenciador
  de senhas, sem extensões, sem notificações do SO.
- CPF/CNPJ, telefone, endereço: nenhum frame pode conter.

## Especificação técnica de saída (o que eu gero na pós)

- `<base>.mp4` — H.264, mudo (sem faixa de áudio), ~8–15 s, largura ≤ 1280 px, **alvo ≤ 300 KB**
  (referência: os atuais têm 150–265 KB). Loop suave.
- `<base>-poster.png` — 1 frame representativo do **estado final** do passo (não o inicial),
  ≤ 1280 px de largura, PNG otimizado (~400–600 KB como os atuais).
- Legenda "N. <ação> — Demonstração · dados fictícios · N/total" queima na pós (padrão atual).
- O componente já trata: `muted`, `loop`, `controls`, sem autoplay sob `prefers-reduced-motion`,
  poster como alternativa estática, `mediaAlt` textual. Não precisa mudar.

## Roteiro por clip (o que gravar na sessão conjunta)

Cada clipe = **uma tela por vez, uma ação clara**. Gravar em tela cheia da aba, depois eu recorto.

### 1. `meu-pluggy` — conectar um banco no MeuPluggy (site: meupluggy.com.br, logado)

1. Tela **Conexões / Data Passport** com 2–4 conexões fictícias.
2. Clicar **+ Nova conexão** → **Continuar**.
3. Tela de escolha da instituição (lista de bancos) — parar aqui (não completar login de banco real).
   `mediaAlt` atual: "Tela de Conexões do MeuPluggy com o botão Nova conexão em destaque". ✅ manter.

### 2. `criar-aplicacao` — abrir/selecionar a aplicação (dashboard.pluggy.ai, logado)

1. **Dashboard → Aplicações**.
2. **Criar aplicação** (ou selecionar "Axon Exemplo" se já existir) — mostrar o nome "Axon Exemplo".
3. Entrar na aplicação (visão geral dela).
   `mediaAlt` atual: "Painel do Pluggy na seção Aplicações, com uma aplicação de exemplo selecionada." — confirmar/atualizar se a navegação mudou.

### 3. `aplicacao` — autorizar a conexão para a aplicação

1. Dentro de "Axon Exemplo": botão de **iniciar demonstração / Conectar Conta**.
2. **Continuar → MeuPluggy → Conectar**.
3. Tela de **escolher a conexão do MeuPluggy** para autorizar à aplicação — parar aqui.
   `mediaAlt` atual: "Fluxo de Conectar Conta da aplicação, na etapa de escolher a conexão do MeuPluggy." ✅

### 4. `credenciais` — copiar Client ID e Client Secret

1. Dentro de "Axon Exemplo", seção de **credenciais / API keys**.
2. Mostrar os rótulos **Client ID** e **Client Secret** e o botão **Copiar** de cada
   (valores **borrados** na pós).
3. Poster = essa tela com os dois campos visíveis.
   `mediaAlt` atual: "Detalhe da aplicação no painel do Pluggy mostrando os campos Client ID e Client Secret, com valores fictícios." ✅ — mas o poster precisa passar a mostrar isso.

### 5. `copiar-item-id` — copiar o Item ID de cada conexão

1. **Aplicações → ▶ (abrir)** da aplicação "Axon Exemplo".
2. Selecionar um **Item** na lista de Itens Conectados.
3. Abrir **⋮** → **Copiar Item ID**. Mostrar o toast/realce de "copiado".
   `mediaAlt` atual: "Sequência no painel do Pluggy: abrir a aplicação, escolher o Item, menu de três pontos, Copiar Item ID." ✅

## Como fazer a sessão

**Michel precisa estar logado** em meupluggy.com.br e dashboard.pluggy.ai (eu não faço login
nem opero a conta). Duas opções:

- **A — Michel grava:** compartilha a tela / grava cada um dos 5 fluxos (QuickTime, Xbox Game
  Bar, OBS, ou a gravação nativa do SO), seguindo o roteiro acima. Salva os 5 arquivos em
  `scratchpad/axf-99-raw/` (ou manda por qualquer canal). Eu faço todo o recorte, borrão,
  legenda, compressão, posters e a integração no static resource + PR.
- **B — ao vivo pelo browser embutido:** eu abro cada site, Michel assume para logar, eu
  navego/clico pelos fluxos e capturo a sequência de telas; monto os clipes a partir delas.
  (O browser embutido não grava vídeo, então o resultado sai de screenshots encadeados.)

Recomendo **A** — vídeo real fica mais claro que screenshots encadeados, e o Michel controla
o que aparece na tela.

## Depois da captura (meu lado)

1. Recortar à área da UI, remover banners de trial, borrar segredos, checar cada frame por PII.
2. Codificar MP4 mudo pequeno + gerar poster do estado final + queimar legenda.
3. Substituir os 10 arquivos em `force-app/main/default/staticresources/AXF_pluggyGuideMedia/`.
4. Ajustar `labels.js` (`mediaAlt`/`body` PT+EN) só se algum fluxo do Pluggy mudou.
5. Deploy AXON_DEV, `npm run test:unit` (guia), validar no wizard, PR → develop, AXF-99 → Em análise.
