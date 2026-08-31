import LANG from "@salesforce/i18n/lang";

/**
 * PT-BR / EN content for the Pluggy setup mini-wizard (AXF-89, AC2–AC9).
 * Component-local i18n (org has no Translation Workbench). PT-BR is the base;
 * EN is used when the user's language starts with "en".
 *
 * External button/menu names (Conexões, Nova conexão, Aplicações, Conectar Conta,
 * Copiar Item ID, …) are kept as the card describes them and are NOT translated —
 * they must match what the user sees on MeuPluggy / dashboard.pluggy.ai.
 */
const PT = {
  chrome: {
    title: "Conectar seus bancos no Pluggy",
    intro: "Guia rápido — uma etapa por vez.",
    stepOf: "Etapa {0} de {1}",
    back: "Voltar",
    next: "Próximo",
    finish: "Concluir",
    openHelp: "Ver mais ajuda",
    closeHelp: "Ocultar ajuda",
    openLink: "Abrir site oficial",
    mediaFictitious: "Demonstração com dados fictícios, sem som.",
    mediaStaticNote:
      "O vídeo repete os passos escritos acima. Use os controles para pausar; a primeira imagem e o texto são a versão completa.",
    reducedMotionNote:
      "Movimento reduzido está ativo: o vídeo não inicia sozinho. Use o controle de play para vê-lo."
  },
  steps: {
    intro: {
      title: "O que você vai fazer",
      body: [
        "Antes de configurar o Axon, você precisa: (1) conectar seus bancos no MeuPluggy e (2) autorizar esses dados para a aplicação certa no painel do Pluggy.",
        "Este guia mostra uma ação por vez. Você pode voltar a qualquer momento. Nada aqui conecta banco nem envia senha — as instruções são só de apoio."
      ]
    },
    meupluggyAccount: {
      title: "Criar ou entrar no MeuPluggy",
      body: [
        "Abra o site oficial do MeuPluggy pelo botão abaixo.",
        "Crie uma conta ou entre com a conta que você já tem."
      ],
      mediaAlt:
        "Tela inicial do MeuPluggy com os botões de criar conta e entrar, com dados fictícios."
    },
    meupluggyConnect: {
      title: "Conectar um banco no MeuPluggy",
      body: [
        "No MeuPluggy, abra Conexões e clique em Nova conexão.",
        "Clique em Continuar, escolha a instituição e conclua a autorização que o banco pedir. Os campos mudam de um banco para outro."
      ],
      mediaAlt:
        "Tela de Conexões do MeuPluggy com o botão Nova conexão em destaque, com dados fictícios.",
      help: [
        "Repita esta etapa para cada banco que você quer disponibilizar ao Axon.",
        "Alguns bancos pedem confirmação no aplicativo do próprio banco ou um código enviado a você."
      ]
    },
    dashboardApp: {
      title: "Abrir a aplicação no painel do Pluggy",
      body: [
        "Abra o painel do Pluggy pelo botão abaixo e entre.",
        "Vá em Dashboard → Aplicações e crie uma aplicação ou selecione a que você vai usar no Axon."
      ],
      mediaAlt:
        "Painel do Pluggy na seção Aplicações, com uma aplicação de exemplo selecionada."
    },
    dashboardConnect: {
      title: "Autorizar a conexão para a aplicação",
      body: [
        "Dentro da aplicação, use o botão de iniciar demonstração e clique em Conectar Conta.",
        "Clique em Continuar → MeuPluggy → Conectar e escolha a conexão disponível para autorizá-la à aplicação."
      ],
      mediaAlt:
        "Fluxo de Conectar Conta da aplicação, na etapa de escolher a conexão do MeuPluggy.",
      help: [
        "Repita a autorização para todas as conexões que você quer que o Axon enxergue.",
        "Só as conexões autorizadas aqui ficam visíveis para a aplicação — não existe lista automática de tudo."
      ]
    },
    credentials: {
      title: "Copiar Client ID e Client Secret",
      body: [
        "Na mesma aplicação do painel do Pluggy, copie o Client ID e o Client Secret.",
        "Ao configurar o Axon, informe esses dois valores no formulário seguro de credenciais. Nunca cole senha de banco nem login do MeuPluggy nesse formulário."
      ],
      action: "Ir para o formulário de credenciais",
      mediaAlt:
        "Detalhe da aplicação no painel do Pluggy mostrando os campos Client ID e Client Secret, com valores fictícios.",
      help: [
        "Client ID e Client Secret identificam a aplicação — não são o seu login do MeuPluggy.",
        "Também não são o consentimento das contas nem um token pessoal do banco.",
        "O Axon guarda essas credenciais só pelo fluxo oficial e seguro; este guia não as recebe."
      ]
    },
    itemId: {
      title: "Copiar o Item ID de uma conexão",
      body: [
        "No painel do Pluggy (dashboard.pluggy.ai), entre e vá em Aplicações. Clique no ▶ da aplicação usada no Axon.",
        "Selecione o Item, abra o menu ⋮ e clique em Copiar Item ID. Cole no Axon e use Buscar contas e cartões."
      ],
      mediaAlt:
        "Sequência no painel do Pluggy: abrir a aplicação, escolher o Item, menu de três pontos, Copiar Item ID.",
      help: [
        "Item ID, Client ID e Client Secret são três coisas diferentes.",
        "Não use recuperação por URL nem Copiar link do MeuPluggy — o caminho é o Item ID pelo painel.",
        "Depois de copiar, você pode Adicionar outra conexão ou Continuar.",
        "Ver a animação até o fim não executa a busca — você ainda precisa colar o Item ID e clicar em Buscar contas e cartões no Axon."
      ]
    },
    historyPeriod: {
      title: "Escolher o período de histórico",
      body: [
        "Antes de buscar contas e cartões, escolha, para cada conexão, quanto histórico trazer.",
        "Há um período sugerido por padrão e a opção de trazer todo o histórico disponível."
      ]
    },
    backgroundImport: {
      title: "O histórico vem em segundo plano",
      body: [
        "Assim que a busca termina, os saldos e a lista atual de contas e cartões já ficam prontos para usar.",
        'O histórico mais antigo é importado em segundo plano ("Histórico em processamento"). Você não precisa esperar para usar o Axon nem para concluir o onboarding.'
      ]
    },
    limitations: {
      title: "Se algo não funcionar",
      body: [
        "Estas situações são diferentes entre si: período de teste do Pluggy expirado; instituição que não aparece na lista; consentimento do banco pendente; conexão que não foi autorizada para a aplicação.",
        "Em qualquer uma delas, o guia aponta o próximo passo seguro. O Axon não promete plano ou acesso gratuito e não contrata nada por você."
      ]
    },
    done: {
      title: "Pronto para configurar o Axon",
      body: [
        "Marcar este guia como lido não conecta nenhum banco, não valida credenciais e não faz a descoberta de contas.",
        "O guia é só instrucional. A verificação real acontece nas telas próprias do Axon, e as credenciais do banco só são informadas no fluxo oficial.",
        "Ao concluir, você volta para o assistente principal."
      ]
    }
  }
};

const EN = {
  chrome: {
    title: "Connect your banks on Pluggy",
    intro: "Quick guide — one step at a time.",
    stepOf: "Step {0} of {1}",
    back: "Back",
    next: "Next",
    finish: "Finish",
    openHelp: "More help",
    closeHelp: "Hide help",
    openLink: "Open official site",
    mediaFictitious: "Demonstration with fictitious data, no sound.",
    mediaStaticNote:
      "The video repeats the written steps above. Use the controls to pause; the first frame and the text are the full version.",
    reducedMotionNote:
      "Reduced motion is on: the video does not start on its own. Use the play control to watch it."
  },
  steps: {
    intro: {
      title: "What you are going to do",
      body: [
        "Before setting up Axon you need to: (1) connect your banks on MeuPluggy and (2) authorize that data for the right application in the Pluggy dashboard.",
        "This guide shows one action at a time. You can go back anytime. Nothing here connects a bank or sends a password — the instructions are support only."
      ]
    },
    meupluggyAccount: {
      title: "Create or sign in to MeuPluggy",
      body: [
        "Open the official MeuPluggy site with the button below.",
        "Create an account or sign in with the account you already have."
      ],
      mediaAlt:
        "MeuPluggy home screen with the create-account and sign-in buttons, using fictitious data."
    },
    meupluggyConnect: {
      title: "Connect a bank on MeuPluggy",
      body: [
        "On MeuPluggy, open Conexões and click Nova conexão.",
        "Click Continuar, choose the institution and complete the authorization the bank asks for. Fields differ from bank to bank."
      ],
      mediaAlt:
        "MeuPluggy Conexões screen with the Nova conexão button highlighted, using fictitious data.",
      help: [
        "Repeat this step for every bank you want to make available to Axon.",
        "Some banks ask for confirmation in their own app or a code sent to you."
      ]
    },
    dashboardApp: {
      title: "Open the application in the Pluggy dashboard",
      body: [
        "Open the Pluggy dashboard with the button below and sign in.",
        "Go to Dashboard → Aplicações and create an application or select the one you will use in Axon."
      ],
      mediaAlt:
        "Pluggy dashboard on the Aplicações section, with a sample application selected."
    },
    dashboardConnect: {
      title: "Authorize the connection for the application",
      body: [
        "Inside the application, use the start-demo button and click Conectar Conta.",
        "Click Continuar → MeuPluggy → Conectar and pick the available connection to authorize it for the application."
      ],
      mediaAlt:
        "Application Conectar Conta flow, on the step where you choose the MeuPluggy connection.",
      help: [
        "Repeat the authorization for every connection you want Axon to see.",
        "Only the connections authorized here are visible to the application — there is no automatic list of everything."
      ]
    },
    credentials: {
      title: "Copy Client ID and Client Secret",
      body: [
        "In the same application in the Pluggy dashboard, copy the Client ID and the Client Secret.",
        "When you set up Axon, enter these two values in the secure credentials form. Never paste a bank password or your MeuPluggy login in that form."
      ],
      action: "Go to the credentials form",
      mediaAlt:
        "Application detail in the Pluggy dashboard showing the Client ID and Client Secret fields, with fictitious values.",
      help: [
        "Client ID and Client Secret identify the application — they are not your MeuPluggy login.",
        "They are also not the account consent nor a personal bank token.",
        "Axon stores these credentials only through the official secure flow; this guide never receives them."
      ]
    },
    itemId: {
      title: "Copy a connection's Item ID",
      body: [
        "In the Pluggy dashboard (dashboard.pluggy.ai), sign in and go to Aplicações. Click the ▶ of the application used in Axon.",
        "Select the Item, open the ⋮ menu and click Copiar Item ID. Paste it in Axon and use Buscar contas e cartões."
      ],
      mediaAlt:
        "Sequence in the Pluggy dashboard: open the application, choose the Item, three-dot menu, Copiar Item ID.",
      help: [
        "Item ID, Client ID and Client Secret are three different things.",
        "Do not use URL recovery or Copiar link on MeuPluggy — the path is the Item ID from the dashboard.",
        "After copying you can Adicionar outra conexão or Continuar.",
        "Watching the animation to the end does not run the search — you still have to paste the Item ID and click Buscar contas e cartões in Axon."
      ]
    },
    historyPeriod: {
      title: "Choose the history period",
      body: [
        "Before fetching accounts and cards, choose, for each connection, how much history to bring.",
        "There is a suggested period by default and an option to bring all available history."
      ]
    },
    backgroundImport: {
      title: "History comes in the background",
      body: [
        "As soon as the fetch finishes, balances and the current list of accounts and cards are ready to use.",
        'Older history is imported in the background ("Histórico em processamento"). You do not need to wait to use Axon or to finish onboarding.'
      ]
    },
    limitations: {
      title: "If something does not work",
      body: [
        "These situations are different from each other: expired Pluggy trial; an institution that is not in the list; a pending bank consent; a connection that was not authorized for the application.",
        "In any of them the guide points to the safe next step. Axon does not promise a free plan or access and does not sign up for anything on your behalf."
      ]
    },
    done: {
      title: "Ready to set up Axon",
      body: [
        "Marking this guide as read does not connect any bank, does not validate credentials and does not run account discovery.",
        "The guide is instructional only. The real check happens on Axon's own screens, and bank credentials are entered only in the official flow.",
        "When you finish, you go back to the main assistant."
      ]
    }
  }
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
