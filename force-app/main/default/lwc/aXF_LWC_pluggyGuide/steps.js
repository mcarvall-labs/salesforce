/**
 * Structure of the Pluggy setup mini-wizard (AXF-89). Language-neutral:
 * ids, which steps carry media / an animation / an inline action, and the
 * official external link (if any). All user-facing text lives in labels.js.
 *
 * Media assets are intentionally absent — each media step renders a labelled
 * placeholder marked "ilustrativa / substituível" (D-87); real sanitised
 * captures land as a later content task.
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
    link: "meupluggy"
  },
  {
    id: "meupluggyConnect",
    media: true,
    animation: false,
    action: null,
    link: "meupluggy",
    help: true
  },
  {
    id: "dashboardApp",
    media: true,
    animation: false,
    action: null,
    link: "dashboard"
  },
  {
    id: "dashboardConnect",
    media: true,
    animation: false,
    action: null,
    link: "dashboard",
    help: true
  },
  {
    id: "credentials",
    media: true,
    animation: false,
    action: "openSecureForm",
    link: "dashboard",
    help: true
  },
  {
    id: "itemId",
    media: true,
    animation: true,
    action: null,
    link: "dashboard",
    help: true
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
