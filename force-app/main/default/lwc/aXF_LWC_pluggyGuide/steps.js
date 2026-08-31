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

export const STEPS = [
  { id: "intro", link: null, action: null, media: null },
  { id: "meupluggyAccount", link: "meupluggy", action: null, media: null },
  {
    id: "meupluggyConnect",
    link: "meupluggy",
    action: null,
    media: "meu-pluggy",
    help: true
  },
  {
    id: "dashboardApp",
    link: "dashboard",
    action: null,
    media: "criar-aplicacao"
  },
  {
    id: "dashboardConnect",
    link: "dashboard",
    action: null,
    media: "aplicacao",
    help: true
  },
  {
    id: "credentials",
    link: "dashboard",
    action: "openSecureForm",
    media: "credenciais",
    help: true
  },
  {
    id: "itemId",
    link: "dashboard",
    action: null,
    media: "copiar-item-id",
    help: true
  },
  { id: "historyPeriod", link: null, action: null, media: null },
  { id: "backgroundImport", link: null, action: null, media: null },
  { id: "limitations", link: null, action: null, media: null },
  { id: "done", link: null, action: null, media: null }
];
