/**
 * Structure of the Pluggy setup mini-wizard (AXF-89). Language-neutral:
 * ids, which steps carry media / an animation / an inline action, the official
 * external link, and a schematic `figure` (a fake window title + the ordered
 * external controls the user clicks). All prose lives in labels.js.
 *
 * The figure renders as an inline SVG diagram with fictitious data — NOT a real
 * screenshot. It is marked "ilustração esquemática — substituível por tela real"
 * (D-87); photo-real sanitised captures replace it as a later content task.
 *
 * `figure.controls` entries are external MeuPluggy / Pluggy dashboard button and
 * menu names — kept verbatim, never translated, so they match what the user sees.
 */
export const OFFICIAL_LINKS = {
  meupluggy: "https://meupluggy.com.br/",
  dashboard: "https://dashboard.pluggy.ai/"
};

export const STEPS = [
  { id: "intro", media: false, animation: false, action: null, link: null },
  {
    id: "meupluggyAccount",
    media: true,
    animation: false,
    action: null,
    link: "meupluggy",
    figure: {
      window: "meupluggy.com.br",
      controls: ["Criar conta", "Entrar"]
    }
  },
  {
    id: "meupluggyConnect",
    media: true,
    animation: false,
    action: null,
    link: "meupluggy",
    help: true,
    figure: {
      window: "MeuPluggy",
      controls: [
        "Conexões",
        "Nova conexão",
        "Continuar",
        "Instituição",
        "Autorizar no banco"
      ]
    }
  },
  {
    id: "dashboardApp",
    media: true,
    animation: false,
    action: null,
    link: "dashboard",
    figure: {
      window: "dashboard.pluggy.ai",
      controls: ["Dashboard", "Aplicações", "Criar ou selecionar aplicação"]
    }
  },
  {
    id: "dashboardConnect",
    media: true,
    animation: false,
    action: null,
    link: "dashboard",
    help: true,
    figure: {
      window: "Aplicação",
      controls: [
        "Iniciar demonstração",
        "Conectar Conta",
        "Continuar",
        "MeuPluggy",
        "Conectar",
        "Autorizar a conexão"
      ]
    }
  },
  {
    id: "credentials",
    media: true,
    animation: false,
    action: "openSecureForm",
    link: "dashboard",
    help: true,
    figure: {
      window: "Aplicação",
      controls: ["Client ID", "Client Secret", "Copiar"]
    }
  },
  {
    id: "itemId",
    media: true,
    animation: true,
    action: null,
    link: "dashboard",
    help: true,
    figure: {
      window: "dashboard.pluggy.ai",
      controls: [
        "Aplicações",
        "▶ da aplicação",
        "Selecionar Item",
        "Menu ⋮",
        "Copiar Item ID"
      ]
    }
  },
  {
    id: "historyPeriod",
    media: false,
    animation: false,
    action: null,
    link: null
  },
  {
    id: "backgroundImport",
    media: false,
    animation: false,
    action: null,
    link: null
  },
  {
    id: "limitations",
    media: false,
    animation: false,
    action: null,
    link: null
  },
  { id: "done", media: false, animation: false, action: null, link: null }
];
