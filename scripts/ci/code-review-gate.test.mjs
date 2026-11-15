import test from "node:test";
import assert from "node:assert/strict";
import {
  LABELS,
  hasManualSteps,
  checkIssue,
  main
} from "./code-review-gate.mjs";

const jira = {
  baseUrl: "https://example.atlassian.net",
  email: "a@b.c",
  token: "t"
};

const jiraApi = (issues) => async (url) => {
  const key = url.match(/issue\/(AXF-\d+)/)[1];
  if (!(key in issues)) return { ok: false, status: 404 };
  return {
    ok: true,
    status: 200,
    json: async () => ({ fields: { labels: issues[key] } })
  };
};

const env = (extra) => ({
  JIRA_BASE_URL: "https://example.atlassian.net/",
  JIRA_USER_EMAIL: "a@b.c",
  JIRA_API_TOKEN: "t",
  ...extra
});

test("hasManualSteps: None means no manual step", () => {
  assert.equal(hasManualSteps("## Deployment Steps\n\nNone\n"), false);
  assert.equal(
    hasManualSteps("## Deployment Steps\r\n\r\n**None**\r\n"),
    false
  );
  assert.equal(
    hasManualSteps(
      "## Description\nx\n\n## Deployment Steps\nNone\n\n## Related work\n- [AXF-1](u)"
    ),
    false
  );
});

test("hasManualSteps: any real step, or the untouched template, counts", () => {
  assert.equal(
    hasManualSteps(
      "## Deployment Steps\n\n### Post-Deployment\n1. Assign the PS\n"
    ),
    true
  );
  assert.equal(
    hasManualSteps(
      "## Deployment Steps\n\n> If none, write None.\n\n### Pre-Deployment\n**Steps:**\n1.\n"
    ),
    true
  );
});

test("hasManualSteps: instructions in blockquotes are ignored and a missing section is not manual", () => {
  assert.equal(
    hasManualSteps(
      "## Deployment Steps\n\n> Describe any manual steps.\n\nNone\n"
    ),
    false
  );
  assert.equal(
    hasManualSteps(
      "## Deployment Steps\n\nNone\n\n\n[AXF-1]: https://x.atlassian.net/browse/AXF-1?atlOrigin=abc"
    ),
    false
  );
  assert.equal(hasManualSteps("## Description\nOnly this.\n"), false);
  assert.equal(hasManualSteps(undefined), false);
});

test("checkIssue passes an approved issue and fails the others", async () => {
  const fetchImpl = jiraApi({
    "AXF-1": [LABELS.approved],
    "AXF-2": [],
    "AXF-3": [LABELS.approved, LABELS.reproved]
  });
  assert.deepEqual(
    (await checkIssue({ jira, key: "AXF-1", manual: false, fetchImpl })).errors,
    []
  );
  const missing = await checkIssue({
    jira,
    key: "AXF-2",
    manual: false,
    fetchImpl
  });
  assert.match(missing.errors[0], /falta passar pelo code review/);
  const reproved = await checkIssue({
    jira,
    key: "AXF-3",
    manual: false,
    fetchImpl
  });
  assert.match(reproved.errors[0], /reprovada/);
});

test("checkIssue requires manual-step only when the PR declares manual steps", async () => {
  const fetchImpl = jiraApi({
    "AXF-1": [LABELS.approved],
    "AXF-2": [LABELS.approved, LABELS.manual]
  });
  const without = await checkIssue({
    jira,
    key: "AXF-1",
    manual: true,
    fetchImpl
  });
  assert.match(without.errors[0], /manual-step/);
  assert.deepEqual(
    (await checkIssue({ jira, key: "AXF-2", manual: true, fetchImpl })).errors,
    []
  );
  assert.deepEqual(
    (await checkIssue({ jira, key: "AXF-1", manual: false, fetchImpl })).errors,
    []
  );
});

test("checkIssue skips an unknown issue and fails on a Jira error", async () => {
  const unknown = await checkIssue({
    jira,
    key: "AXF-9",
    manual: false,
    fetchImpl: jiraApi({})
  });
  assert.equal(unknown.skipped, true);
  await assert.rejects(
    checkIssue({
      jira,
      key: "AXF-9",
      manual: false,
      fetchImpl: async () => ({ ok: false, status: 500 })
    }),
    /500/
  );
});

test("main passes when no Jira key is named", async () => {
  const logs = await main(
    env({ PR_TITLE: "ci: tweak workflow", PR_HEAD_REF: "ci/tweak" }),
    jiraApi({})
  );
  assert.deepEqual(logs, []);
});

test("main checks every key of a collective promotion", async () => {
  await assert.rejects(
    main(
      env({ PR_TITLE: "AXF-1 AXF-2: develop", PR_HEAD_REF: "feature/x" }),
      jiraApi({ "AXF-1": [LABELS.approved], "AXF-2": [] })
    ),
    /Merge blocked/
  );
  const results = await main(
    env({ PR_TITLE: "AXF-1 AXF-2: develop", PR_HEAD_REF: "feature/x" }),
    jiraApi({ "AXF-1": [LABELS.approved], "AXF-2": [LABELS.approved] })
  );
  assert.equal(results.length, 2);
});

test("main reads the live pull request when a number and token are given", async () => {
  const fetchImpl = async (url) => {
    if (url.startsWith("https://api.github.com/")) {
      assert.match(url, /\/pulls\/42$/);
      return {
        ok: true,
        status: 200,
        json: async () => ({
          title: "AXF-1: develop",
          head: { ref: "feature/axf-1" },
          body: "## Deployment Steps\n\nNone\n"
        })
      };
    }
    return jiraApi({ "AXF-1": [LABELS.approved] })(url);
  };
  const results = await main(
    env({
      PR_NUMBER: "42",
      GH_TOKEN: "g",
      GITHUB_REPOSITORY: "o/r",
      PR_TITLE: "stale title",
      PR_HEAD_REF: "stale"
    }),
    fetchImpl
  );
  assert.equal(results[0].key, "AXF-1");
});
