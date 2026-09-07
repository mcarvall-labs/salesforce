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

## Executado — v2 (06/09/2026): 7 screencasts + guia reestruturado

O product owner pediu vídeos "parecendo gravados de verdade" — navegação, digitação,
zoom, mouse ponto-a-ponto, transições. O guia foi **reestruturado para 7 passos com
mídia** (antes 5), um por tutorial:

| # | step id (novo) | fonte | o que mostra |
| - | -------------- | ----- | ------------ |
| 1 | `meupluggyAccount`       | pasta 1 | digita `meupluggy.com.br` → Criar conta → login por e-mail |
| 2 | `meupluggyConnectFirst`  | pasta 2 | Conectar minha conta → instituição → CPF (fictício) → autorizar → conta conectada |
| 3 | `meupluggyConnectNext`   | pasta 3 | Nova conexão → 2º banco (Itaú sobre Santander) → 2 conexões ativas |
| 4 | `dashboardApp`           | pasta 4 | digita `dashboard.pluggy.ai` → Aplicações → Novo |
| 5 | `credentials`            | pasta 4 | copiar Client ID + Client Secret (borrados) → colar no Axon |
| 6 | `dashboardConnect`       | pasta 4 | Conectar Conta → autorizar as conexões ao app |
| 7 | `itemId`                 | pasta 5 | app → Item → ⋮ → Copiar Item ID → colar/registrar no wizard do Axon |

- Engine própria (`scratchpad/studio.py` + `render.py` + `build_studio.py`): barra de
  navegador sintética com digitação de URL + "carregamento", cursor com easing +
  anel de clique, digitação em campos com caret, zoom-punch, transições
  crossfade/slide/dip, card de título, legenda lower-third. Encode por pipe
  `libx264` (ShareX ffmpeg), CRF 28, `yuv420p`, `+faststart`. 1280×720, 11–21 s,
  200–615 KB.
- Anonimização: nome real → "Ana"/"A"; Client ID/Secret/API Key → exemplo; Item ID
  real (`f1a652d5…`, `d89b6828…`) → `0000000-0000-4000-8000-000000000002`; contas
  → DEMO-00N / 000N; saldos/limite → fictícios; CPF digitado → `000.000.000-00`;
  cursores nativos dos screenshots pintados por cima; banners de trial/offline e
  widget de suporte removidos; bancos reais mantidos.
- `steps.js` reestruturado (fase credentials: intro + 1–5; fase discovery:
  discoveryIntro + 6 + 7 + historyPeriod/backgroundImport/limitations/done).
  `labels.js` PT+EN: `meupluggyConnect` → `meupluggyConnectFirst` +
  `meupluggyConnectNext`; `intro` atualizado (5 itens); `dashboardConnect` movido
  para a fase discovery. `aXF_LWC_pluggyGuide.js`/`.html` **sem mudança** (leem
  `step.media`). jest 12/12. Deploy AXON_DEV OK.
- Screenshots reais do Michel em `_bmad-output/pluggy-screenshots/` **não** entram
  no repo. Os 10 arquivos antigos de mídia foram substituídos pelos 14 novos.

## Executado — v1 (06/09/2026, superado pela v2)

Michel entregou ~78 screenshots reais em `_bmad-output/pluggy-screenshots/` (5 fluxos).
Os 5 pares `.mp4`+`-poster.png` foram **regerados a partir desses screenshots reais**, não
mais dos mockups da fase UX.

| clip              | telas usadas (pasta `pluggy-screenshots`)                                                             | anonimização aplicada                                                                                                              |
| ----------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `meu-pluggy`      | `3/chrome_4knJkYnj2p`, `2/chrome_XiJdan2OId`, `2/chrome_MC1JudJWBL`, `2/chrome_OYmIrINwe7`, `2/chrome_XHnojWYyWa` | avatar `M`→`A`; saldos/limite/final de cartão → fictícios (R$ 1.500 / R$ 320 / xxxx 0001). Frames com CPF descartados. |
| `criar-aplicacao` | `4/chrome_OHodlkQLZu`, `4/chrome_RK6an1uWTm`                                                          | "Bem-vindo de volta, Michel!" → "Bem-vindo de volta!"; banner "Faça um tour" removido; banners de trial/offline recortados; Client ID real → `axon-exemplo-client-id`; avatar→`A`. |
| `credenciais`     | `4/chrome_RK6an1uWTm`, `4/chrome_RxxEYt01d7`                                                          | Client ID real → `axon-exemplo-client-id`; API Key (JWT) → texto de exemplo; Client Secret já vinha mascarado.       |
| `aplicacao`       | `4/chrome_EKm5GxZa3k`, `4/chrome_vzBTEC4oZC`, `4/chrome_cJo8taWKPj`                                   | IDs de conexão (`2fa28325`, `4d4fa69f`) → `DEMO-001`/`DEMO-002`; banners de trial/offline recortados; avatar→`A`.    |
| `copiar-item-id`  | `5/chrome_0QdHUZ1OMg`, `5/chrome_D3ayHcU8KV`                                                          | Item ID real `f1a652d5-…` → `0000000-0000-4000-8000-000000000002`; conta `00022740-6` → `DEMO-001`; final de cartão `3576`/`6644` → `0001`/`0002`; saldo → R$ 250,00; widget WhatsApp e banners removidos; avatar→`A`. |

- Bancos reais (Itaú, Santander) mantidos — permitido pela regra de anonimização.
- Todos os clipes: H.264 mudo, 1200×700, **40–145 KB**, ~7–15 s, cursor animado que desliza
  até o botão + anel de pulso no clique, legenda "<ação> · Demonstração · dados fictícios"
  queimada. Posters = frame do estado final.
- Pipeline: `scratchpad/anon.py` + `scratchpad/build_videos.py` (PIL para redação/composição,
  `C:\Program Files\ShareX\ffmpeg.exe` `libx264` para encode). Screenshots reais do Michel
  **não** entram no repo.
- `labels.js` **não** mudou — os `mediaAlt`/`body` (PT+EN) já descreviam os fluxos de forma
  genérica e continuam corretos.
- `aXF_LWC_pluggyGuide` jest: 12/12. Deploy AXON_DEV: OK.
