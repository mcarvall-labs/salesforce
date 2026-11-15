import test from "node:test";
import assert from "node:assert/strict";
import {
  RULES,
  DEPLOY_RULE,
  extractKeys,
  moveIssue,
  deployTexts,
  main
} from "./jira-status.mjs";

const jira = {
  baseUrl: "https://example.atlassian.net",
  email: "a@b.c",
  token: "t"
};

const jiraApi = ({ status, transitions = [], found = true }) => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, method: options.method ?? "GET", body: options.body });
    if (!found) return { ok: false, status: 404 };
    if (url.includes("?fields=status")) {
      return {
        ok: true,
        status: 200,
        json: async () => ({ fields: { status: { name: status } } })
      };
    }
    if (options.method === "POST") return { ok: true, status: 204 };
    return { ok: true, status: 200, json: async () => ({ transitions }) };
  };
  return { calls, fetchImpl };
};

test("extractKeys finds keys in branches, titles and messages, uppercased and unique", () => {
  assert.deepEqual(
    extractKeys(
      "feature/axf-12-x",
      "AXF-12: fix",
      "Merge from bugfix/AXF-7-y",
      null
    ),
    ["AXF-12", "AXF-7"]
  );
  assert.deepEqual(extractKeys("chore/remove-docs"), []);
});

test("deploy branches map to the environment rules", () => {
  assert.deepEqual(DEPLOY_RULE, { develop: "dev", uat: "uat", main: "prod" });
});

test("moveIssue transitions by destination status name when the status is eligible", async () => {
  const { calls, fetchImpl } = jiraApi({
    status: "Backlog",
    transitions: [
      { id: "7", to: { name: "Cancelada" } },
      { id: "2", to: { name: "Em andamento" } }
    ]
  });
  const line = await moveIssue({
    jira,
    key: "AXF-1",
    rule: RULES.branch,
    fetchImpl
  });
  assert.equal(line, "AXF-1: Backlog -> Em andamento");
  const post = calls.at(-1);
  assert.equal(post.method, "POST");
  assert.deepEqual(JSON.parse(post.body), { transition: { id: "2" } });
});

test("moveIssue never skips a stage", async () => {
  const { calls, fetchImpl } = jiraApi({ status: "Em andamento" });
  const line = await moveIssue({
    jira,
    key: "AXF-1",
    rule: RULES.uat,
    fetchImpl
  });
  assert.match(line, /not eligible/);
  assert.equal(
    calls.some((call) => call.method === "POST"),
    false
  );
});

test("moveIssue accepts the legacy IN UAT status name", async () => {
  const { fetchImpl } = jiraApi({
    status: "No DEV",
    transitions: [{ id: "41", to: { name: "IN UAT" } }]
  });
  assert.equal(
    await moveIssue({ jira, key: "AXF-1", rule: RULES.uat, fetchImpl }),
    "AXF-1: No DEV -> IN UAT"
  );
});

test("moveIssue skips unknown issues and fails when the transition is missing", async () => {
  const missing = jiraApi({ found: false });
  assert.match(
    await moveIssue({
      jira,
      key: "AXF-9",
      rule: RULES.dev,
      fetchImpl: missing.fetchImpl
    }),
    /not found/
  );
  const noTransition = jiraApi({ status: "Em revisão", transitions: [] });
  await assert.rejects(
    moveIssue({
      jira,
      key: "AXF-1",
      rule: RULES.dev,
      fetchImpl: noTransition.fetchImpl
    }),
    /no transition/
  );
});

test("deployTexts reads the commit range and the pull requests of each commit", async () => {
  const github = async (url) => {
    const ok = (body) => ({ ok: true, status: 200, json: async () => body });
    if (url.includes("/compare/")) {
      return ok({
        commits: [{ sha: "c1", commit: { message: "AXF-5: add" } }]
      });
    }
    if (url.endsWith("/pulls"))
      return ok([{ title: "AXF-6 title", head: { ref: "feature/axf-6-x" } }]);
    return { ok: false, status: 404 };
  };
  const texts = await deployTexts(
    {
      GITHUB_REPOSITORY: "o/r",
      GH_TOKEN: "x",
      BEFORE_SHA: "b1",
      AFTER_SHA: "a1"
    },
    github
  );
  assert.deepEqual(extractKeys(...texts), ["AXF-5", "AXF-6"]);
});

test("main does nothing without a key and rejects an unknown rule", async () => {
  assert.deepEqual(await main({ RULE: "branch", REF_NAME: "chore/x" }), []);
  await assert.rejects(main({ RULE: "nope" }), /Unknown RULE/);
});

test("main moves the issue found in the branch name", async () => {
  const { fetchImpl } = jiraApi({
    status: "Backlog",
    transitions: [{ id: "2", to: { name: "Em andamento" } }]
  });
  const results = await main(
    {
      RULE: "branch",
      REF_NAME: "feature/axf-30-x",
      JIRA_BASE_URL: "https://example.atlassian.net/",
      JIRA_USER_EMAIL: "a@b.c",
      JIRA_API_TOKEN: "t"
    },
    fetchImpl
  );
  assert.deepEqual(results, ["AXF-30: Backlog -> Em andamento"]);
});
