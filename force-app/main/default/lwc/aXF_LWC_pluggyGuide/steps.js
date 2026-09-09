/**
 * Structure of the Pluggy setup mini-wizard (AXF-89 / AXF-99). Language-neutral:
 * ids, the official external link, and — for the seven tutorial steps — the base
 * name of an anonymised MP4 screencast held in the `AXF_pluggyGuideMedia` static
 * resource (`<base>.mp4` + `<base>-poster.png`). All prose lives in labels.js.
 *
 * The screencasts were produced from real dashboard.pluggy.ai / meupluggy.com.br
 * captures supplied by the product owner and anonymised with fictitious data
 * (person "Ana"/"A", accounts DEMO-00N, Item UUID 0000…0002, Client ID
 * "axon-exemplo-client-id", CPF 000.000.000-00). Banks keep their real names.
 * They can be replaced by swapping the static resource — no code change.
 *
 * Five base names are historical (meu-pluggy, criar-aplicacao, aplicacao,
 * credenciais, copiar-item-id) and now carry the re-shot screencast for their
 * step; two are new (meupluggyAccount, meupluggyConnectNext).
 */
export const OFFICIAL_LINKS = {
  meupluggy: "https://meupluggy.com.br/",
  dashboard: "https://dashboard.pluggy.ai/"
};

/**
 * `phase` splits the guide in two (AXF-89 revisão / AXF-98):
 *  - "credentials" — shown on the wizard's Pluggy credentials step: create the
 *    MeuPluggy account, connect the first bank, connect the next banks, create
 *    the Pluggy application, copy Client ID + Client Secret.
 *  - "discovery" — shown on the wizard's "find accounts and cards" step:
 *    authorize the connections for the application, copy the Item ID of EACH
 *    connection, history period, background import, limitations.
 * The component renders only the steps of its current `phase`.
 */
export const STEPS = [
  { id: "intro", phase: "credentials", link: null, action: null, media: null },
  {
    id: "meupluggyAccount",
    phase: "credentials",
    link: "meupluggy",
    action: null,
    media: "meupluggyAccount"
  },
  {
    id: "meupluggyConnectFirst",
    phase: "credentials",
    link: "meupluggy",
    action: null,
    media: "meu-pluggy",
    help: true
  },
  {
    id: "meupluggyConnectNext",
    phase: "credentials",
    link: "meupluggy",
    action: null,
    media: "meupluggyConnectNext",
    help: true
  },
  {
    id: "dashboardApp",
    phase: "credentials",
    link: "dashboard",
    action: null,
    media: "criar-aplicacao"
  },
  {
    id: "credentials",
    phase: "credentials",
    link: "dashboard",
    action: "openSecureForm",
    media: "credenciais",
    help: true
  },
  {
    id: "discoveryIntro",
    phase: "discovery",
    link: null,
    action: null,
    media: null
  },
  {
    id: "dashboardConnect",
    phase: "discovery",
    link: "dashboard",
    action: null,
    media: "aplicacao",
    help: true
  },
  {
    id: "itemId",
    phase: "discovery",
    link: "dashboard",
    action: null,
    media: "copiar-item-id",
    help: true
  },
  {
    id: "historyPeriod",
    phase: "discovery",
    link: null,
    action: null,
    media: null
  },
  {
    id: "backgroundImport",
    phase: "discovery",
    link: null,
    action: null,
    media: null
  },
  {
    id: "limitations",
    phase: "discovery",
    link: null,
    action: null,
    media: null
  },
  { id: "done", phase: "discovery", link: null, action: null, media: null }
];

/** The ordered step list for one phase. */
export function stepsForPhase(phase) {
  const p = phase === "discovery" ? "discovery" : "credentials";
  return STEPS.filter((s) => s.phase === p);
}
