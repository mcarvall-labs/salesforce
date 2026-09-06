/**
 * Structure of the Pluggy setup mini-wizard (AXF-89). Language-neutral:
 * ids, the official external link, and — for the five tutorial steps — the base
 * name of an anonymised MP4 demonstration held in the `AXF_pluggyGuideMedia`
 * static resource (`<base>.mp4` + `<base>-poster.png`). All prose lives in
 * labels.js.
 *
 * The MP4s and posters were produced in the UX design phase from screenshots
 * supplied by the product owner, anonymised with fictitious data (person "Ana",
 * accounts DEMO-001…, Item UUID 0000…0002, app badge "Axon Exemplo"). Source:
 * _bmad-output/planning-artifacts/ux-designs/.../pluggy-tutoriais-v2 and
 * pluggy-item-id-v2. Photo-real captures can replace them by swapping the
 * static resource — no code change.
 */
export const OFFICIAL_LINKS = {
  meupluggy: "https://meupluggy.com.br/",
  dashboard: "https://dashboard.pluggy.ai/"
};

/**
 * `phase` splits the guide in two (AXF-89 revisão / AXF-98):
 *  - "credentials" — shown on the wizard's Pluggy credentials step: create the
 *    MeuPluggy account, connect the banks via Open Finance, create the Pluggy
 *    application, copy Client ID + Client Secret.
 *  - "discovery" — shown on the wizard's "find accounts and cards" step: copy the
 *    Item ID of EACH connection, history period, background import, limitations.
 * The component renders only the steps of its current `phase`.
 */
export const STEPS = [
  { id: "intro", phase: "credentials", link: null, action: null, media: null },
  {
    id: "meupluggyAccount",
    phase: "credentials",
    link: "meupluggy",
    action: null,
    media: null
  },
  {
    id: "meupluggyConnect",
    phase: "credentials",
    link: "meupluggy",
    action: null,
    media: "meu-pluggy",
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
    id: "dashboardConnect",
    phase: "credentials",
    link: "dashboard",
    action: null,
    media: "aplicacao",
    help: true
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
