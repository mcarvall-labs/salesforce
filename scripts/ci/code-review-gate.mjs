import { pathToFileURL } from "node:url";
import { extractKeys } from "./jira-status.mjs";

/**
 * Merge gate for `develop`: every Jira issue named by the pull request must
 * have passed the code review (`/mic-code-review`, which wraps bmad-code-review)
 * and carry the `code-review-approved` label. An issue whose PR declares manual
 * deployment steps must also carry `manual-step`.
 * Rules: agent-docs/rules/project/16-status.md.
 */
export const LABELS = {
  approved: "code-review-approved",
  reproved: "code-review-reproved",
  manual: "manual-step"
};

const request = async (fetchImpl, url, options) => {
  const response = await fetchImpl(url, options);
  if (!response.ok && response.status !== 404) {
    throw new Error(`${options?.method ?? "GET"} ${url} -> ${response.status}`);
  }
  return response;
};

// The "Deployment Steps" section of the PR template: "None" means no manual
// step. The template's own instructions (blockquotes) are ignored, so an
// untouched template counts as manual steps and the author must answer it.
export function hasManualSteps(body) {
  const match = String(body ?? "").match(
    /^##\s+Deployment Steps\s*$([\s\S]*?)(?=^##\s(?!#)|(?![\s\S]))/im
  );
  if (!match) return false;
  const answer = match[1]
    .split(/\r?\n/)
    .filter(
      (line) =>
        !line.trim().startsWith(">") && !/^\s{0,3}\[[^\]]+\]:\s/.test(line)
    )
    .join("")
    .replace(/[\s*_`]/g, "")
    .toLowerCase();
  return answer !== "" && answer !== "none";
}

export async function checkIssue({ jira, key, manual, fetchImpl = fetch }) {
  const headers = {
    Authorization: `Basic ${Buffer.from(`${jira.email}:${jira.token}`).toString("base64")}`,
    Accept: "application/json"
  };
  const response = await request(
    fetchImpl,
    `${jira.baseUrl}/rest/api/3/issue/${key}?fields=labels`,
    { headers }
  );
  if (response.status === 404) {
    return { key, skipped: true, errors: [] };
  }
  const labels = (await response.json()).fields.labels ?? [];
  const errors = [];
  if (labels.includes(LABELS.reproved)) {
    errors.push(
      `${key}: reprovada no code review (${LABELS.reproved}). Corrija e rode /mic-code-review ${key} de novo.`
    );
  } else if (!labels.includes(LABELS.approved)) {
    errors.push(
      `${key}: falta passar pelo code review. Rode /mic-code-review ${key} neste PR; a label ${LABELS.approved} libera o merge.`
    );
  }
  if (manual && !labels.includes(LABELS.manual)) {
    errors.push(
      `${key}: o PR declara passos manuais em "Deployment Steps", mas a US não tem a label ${LABELS.manual}.`
    );
  }
  return { key, skipped: false, errors };
}

// Title, branch and body are read live so a re-run after the label was applied
// (or after the PR body was edited) judges the current state, not the event
// payload that started the run.
async function pullRequest(env, fetchImpl) {
  const live = { title: env.PR_TITLE, ref: env.PR_HEAD_REF, body: env.PR_BODY };
  if (!env.PR_NUMBER || !env.GH_TOKEN) return live;
  const response = await request(
    fetchImpl,
    `https://api.github.com/repos/${env.GITHUB_REPOSITORY}/pulls/${env.PR_NUMBER}`,
    {
      headers: {
        Authorization: `Bearer ${env.GH_TOKEN}`,
        Accept: "application/vnd.github+json"
      }
    }
  );
  if (response.status === 404) return live;
  const data = await response.json();
  return { title: data.title, ref: data.head.ref, body: data.body };
}

export async function main(env = process.env, fetchImpl = fetch) {
  const pr = await pullRequest(env, fetchImpl);
  const keys = extractKeys(pr.title, pr.ref);
  if (!keys.length) {
    console.log("No Jira key in the PR title or branch; nothing to gate.");
    return [];
  }
  const jira = {
    baseUrl: env.JIRA_BASE_URL.replace(/\/$/, ""),
    email: env.JIRA_USER_EMAIL,
    token: env.JIRA_API_TOKEN
  };
  const manual = hasManualSteps(pr.body);
  const results = [];
  for (const key of keys) {
    results.push(await checkIssue({ jira, key, manual, fetchImpl }));
  }
  for (const result of results) {
    console.log(
      result.skipped
        ? `${result.key}: not found in Jira; skipped.`
        : result.errors.length
          ? result.errors.join("\n")
          : `${result.key}: ${LABELS.approved} ok.`
    );
  }
  const errors = results.flatMap((result) => result.errors);
  if (errors.length) {
    throw new Error(`Merge blocked: ${errors.length} problem(s) above.`);
  }
  return results;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
