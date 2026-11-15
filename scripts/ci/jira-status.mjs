import { pathToFileURL } from "node:url";

/**
 * Moves Jira issues (AXF-123) along the delivery lifecycle from Git events.
 * Each rule only advances an issue that is in one of its `from` statuses, so a
 * story never skips a stage and re-runs are harmless. Transitions are resolved
 * by destination status name, never by a hard-coded transition id.
 * Lifecycle: agent-docs/rules/project/16-status.md.
 */
export const RULES = {
  branch: { to: ["Em andamento"], from: ["Backlog"] },
  review: { to: ["Em revisão"], from: ["Backlog", "Em andamento"] },
  dev: { to: ["No DEV"], from: ["Em andamento", "Em revisão"] },
  uat: { to: ["No UAT", "IN UAT"], from: ["No DEV"] },
  prod: { to: ["Em PROD"], from: ["No UAT", "IN UAT"] }
};

export const DEPLOY_RULE = { develop: "dev", uat: "uat", main: "prod" };

const MAX_COMMITS = 100;
const ZERO_SHA = /^0+$/;

export const extractKeys = (...texts) => [
  ...new Set(
    texts.flatMap((text) =>
      (String(text ?? "").match(/\bAXF-\d+\b/gi) ?? []).map((key) =>
        key.toUpperCase()
      )
    )
  )
];

const request = async (fetchImpl, url, options) => {
  const response = await fetchImpl(url, options);
  if (!response.ok && response.status !== 404) {
    throw new Error(`${options?.method ?? "GET"} ${url} -> ${response.status}`);
  }
  return response;
};

export async function moveIssue({ jira, key, rule, fetchImpl = fetch }) {
  const headers = {
    Authorization: `Basic ${Buffer.from(`${jira.email}:${jira.token}`).toString("base64")}`,
    Accept: "application/json",
    "Content-Type": "application/json"
  };
  const issueUrl = `${jira.baseUrl}/rest/api/3/issue/${key}`;
  const issue = await request(fetchImpl, `${issueUrl}?fields=status`, {
    headers
  });
  if (issue.status === 404) return `${key}: not found in Jira, skipped`;
  const current = (await issue.json()).fields.status.name;
  if (!rule.from.includes(current)) {
    return `${key}: ${current} is not eligible for ${rule.to[0]}, skipped`;
  }
  const { transitions } = await (
    await request(fetchImpl, `${issueUrl}/transitions`, { headers })
  ).json();
  const transition = transitions.find((item) => rule.to.includes(item.to.name));
  if (!transition) {
    throw new Error(`${key}: no transition to ${rule.to.join(" / ")}`);
  }
  await request(fetchImpl, `${issueUrl}/transitions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ transition: { id: transition.id } })
  });
  return `${key}: ${current} -> ${transition.to.name}`;
}

const github = (env, fetchImpl) => async (path) => {
  const response = await request(
    fetchImpl,
    `https://api.github.com/repos/${env.GITHUB_REPOSITORY}${path}`,
    {
      headers: {
        Authorization: `Bearer ${env.GH_TOKEN}`,
        Accept: "application/vnd.github+json"
      }
    }
  );
  return response.status === 404 ? null : response.json();
};

export async function deployTexts(env, fetchImpl = fetch) {
  const get = github(env, fetchImpl);
  const range =
    env.BEFORE_SHA && !ZERO_SHA.test(env.BEFORE_SHA)
      ? await get(`/compare/${env.BEFORE_SHA}...${env.AFTER_SHA}`)
      : null;
  const commits = (
    range?.commits ?? [await get(`/commits/${env.AFTER_SHA}`)]
  ).slice(-MAX_COMMITS);
  const texts = [];
  for (const commit of commits.filter(Boolean)) {
    texts.push(commit.commit.message);
    const pulls = (await get(`/commits/${commit.sha}/pulls`)) ?? [];
    for (const pull of pulls) texts.push(pull.title, pull.head.ref);
  }
  return texts;
}

export async function main(env = process.env, fetchImpl = fetch) {
  const rule = RULES[env.RULE];
  if (!rule) throw new Error(`Unknown RULE "${env.RULE}"`);
  const texts =
    env.RULE === "branch"
      ? [env.REF_NAME]
      : env.RULE === "review"
        ? [env.PR_TITLE, env.PR_HEAD_REF]
        : await deployTexts(env, fetchImpl);
  const keys = extractKeys(...texts);
  if (!keys.length) {
    console.log("No Jira key found; nothing to do.");
    return [];
  }
  const jira = {
    baseUrl: env.JIRA_BASE_URL.replace(/\/$/, ""),
    email: env.JIRA_USER_EMAIL,
    token: env.JIRA_API_TOKEN
  };
  const results = [];
  for (const key of keys) {
    const line = await moveIssue({ jira, key, rule, fetchImpl });
    console.log(line);
    results.push(line);
  }
  return results;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
