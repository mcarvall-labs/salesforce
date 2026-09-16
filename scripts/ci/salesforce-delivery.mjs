import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";

export function sourcePaths(entries) {
  const paths = new Set();
  for (const { status, file } of entries) {
    if (status === "D")
      throw new Error(
        `Deletion requires a reviewed destructive deployment: ${file}`
      );
    if (!file.startsWith("force-app/") || /[\r\n]/.test(file))
      throw new Error("Invalid metadata path");
    const bundle = file.match(/^(force-app\/.*\/(?:aura|lwc)\/[^/]+)\//);
    paths.add(bundle ? bundle[1] : file);
  }
  return [...paths].sort();
}

export function extractDeclaredTests(body) {
  const heading = /^#{1,6}\s*apex test classes to run\s*$/im.exec(body || "");
  if (!heading) return [];
  const rest = body.slice(heading.index + heading[0].length);
  // The PR template's answer area is the first fenced code block after the
  // heading; class names inside it may be separated by spaces and/or commas.
  const fence = /```[^\n]*\n([\s\S]*?)```/.exec(rest);
  if (!fence) return [];
  const names = [];
  for (const token of fence[1].split(/[\s,]+/)) {
    const name = token.trim();
    if (/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) names.push(name);
  }
  return [...new Set(names)];
}

export function testPlan(paths, readFile, declaredTests) {
  const testsInDelta = [];
  let hasProductionApex = false;
  for (const p of paths) {
    if (p.endsWith(".trigger")) {
      hasProductionApex = true;
      continue;
    }
    if (!p.endsWith(".cls")) continue;
    if (/@istest/i.test(readFile(p)))
      testsInDelta.push(path.basename(p, ".cls"));
    else hasProductionApex = true;
  }
  const tests = [...new Set([...testsInDelta, ...declaredTests])];
  if (hasProductionApex && tests.length === 0)
    throw new Error(
      "Changed Apex classes/triggers have no test coverage in this delta. List the " +
        "Apex test class name(s) that cover this change in the PR description's " +
        '"### Apex test classes to run" code block (space/comma-separated), or ' +
        "include the corresponding test class(es) in this PR."
    );
  return {
    testLevel: tests.length ? "RunSpecifiedTests" : "RunLocalTests",
    tests
  };
}

export function completed(payload, exitCode) {
  return (
    exitCode === 0 &&
    payload.status === 0 &&
    payload.result?.done === true &&
    payload.result?.success === true &&
    payload.result?.status === "Succeeded"
  );
}

export function safeResult(payload) {
  const r = payload.result || {};
  const array = (v) => (v ? (Array.isArray(v) ? v : [v]) : []);
  const clean = (v) =>
    String(v ?? "")
      .replace(/force:\/\/\S+|Bearer\s+\S+/gi, "[REDACTED]")
      .slice(0, 1500);
  return {
    id: r.id,
    status: r.status,
    done: r.done,
    success: r.success,
    numberComponentsTotal: r.numberComponentsTotal,
    numberComponentErrors: r.numberComponentErrors,
    numberTestsCompleted: r.numberTestsCompleted,
    numberTestErrors: r.numberTestErrors,
    componentFailures: array(r.details?.componentFailures).map((f) => ({
      component: clean(f.fullName),
      file: clean(f.fileName),
      line: f.lineNumber,
      problem: clean(f.problem)
    })),
    testFailures: array(r.details?.runTestResult?.failures).map((f) => ({
      test: clean(`${f.name}.${f.methodName}`),
      message: clean(f.message)
    }))
  };
}

function command(bin, args) {
  const result = spawnSync(bin, args, {
    encoding: "utf8",
    maxBuffer: 40 * 1024 * 1024
  });
  if (result.error || result.status !== 0)
    throw new Error(
      `${bin} command failed; inspect the configured credentials, baseline and commit ancestry.`
    );
  return result.stdout.trim();
}

function changes(base, head) {
  const fields = command("git", [
    "diff",
    "--no-renames",
    "--name-status",
    "-z",
    base,
    head,
    "--",
    "force-app"
  ]).split("\0");
  if (!fields[0]) return [];
  const entries = [];
  for (let i = 0; i < fields.length - 1; i += 2)
    entries.push({ status: fields[i], file: fields[i + 1] });
  return entries;
}

export async function run() {
  const e = process.env;
  const directory = e.EVIDENCE_DIR;
  if (!directory) throw new Error("EVIDENCE_DIR is required");
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, "source-paths.txt"), "");
  const report = {
    operation: e.OPERATION,
    environment: e.TARGET_ENV,
    sha: e.GITHUB_SHA,
    outcome: "Failed",
    paths: []
  };
  let authFile;
  try {
    const validEnvs = {
      DEV: "develop",
      UAT: "uat",
      PROD: "main"
    };
    if (
      !Object.keys(validEnvs).includes(e.TARGET_ENV) ||
      !["validate", "deploy"].includes(e.OPERATION)
    )
      throw new Error("Only DEV/UAT/PROD pipeline operations are allowed");
    const branch = validEnvs[e.TARGET_ENV];
    if (e.TARGET_BRANCH !== branch)
      throw new Error("Branch/environment mismatch");
    if (
      e.OPERATION === "deploy" &&
      (e.GITHUB_EVENT_NAME !== "push" ||
        e.GITHUB_REF !== `refs/heads/${branch}`)
    )
      throw new Error("Deploy requires a protected branch push");
    // The delta is always computed from the PR base branch commit (from) to the
    // target/head commit being validated or deployed (to) — never from deploy history.
    let baseSha, prBody;
    if (e.OPERATION === "deploy") {
      const prs = JSON.parse(
        command("gh", [
          "api",
          `repos/${e.GITHUB_REPOSITORY}/commits/${e.GITHUB_SHA}/pulls`
        ])
      );
      const mergedPr = prs.find(
        (pr) =>
          pr.merged_at &&
          pr.base.ref === branch &&
          pr.merge_commit_sha === e.GITHUB_SHA
      );
      if (!mergedPr)
        throw new Error(
          "Deploy requires a merged pull request for this exact commit"
        );
      baseSha = mergedPr.base.sha;
      prBody = mergedPr.body || "";
    } else {
      baseSha = e.PR_BASE_SHA;
      prBody = e.PR_BODY || "";
    }
    if (!/^[0-9a-f]{40}$/.test(baseSha || ""))
      throw new Error(
        "Could not resolve the PR base branch commit (from) to diff against the target commit (to)"
      );
    command("git", ["merge-base", "--is-ancestor", baseSha, e.GITHUB_SHA]);
    report.base = baseSha;
    report.paths = sourcePaths(changes(baseSha, e.GITHUB_SHA));
    fs.writeFileSync(
      path.join(directory, "source-paths.txt"),
      report.paths.join("\n") + "\n"
    );
    if (!report.paths.length) {
      report.outcome = "No metadata changes";
      return;
    }
    // Package the exact validated/deployed delta as mdapi-format metadata so the
    // evidence artifact carries the same content submitted to Salesforce.
    const packageDir = path.join(
      e.RUNNER_TEMP,
      `delta-package-${e.GITHUB_RUN_ID}-${e.GITHUB_RUN_ATTEMPT || 1}`
    );
    command("sf", [
      "project",
      "convert",
      "source",
      "--output-dir",
      packageDir,
      ...report.paths.flatMap((p) => ["--source-dir", p])
    ]);
    const zip = spawnSync(
      "zip",
      ["-r", path.join(directory, "delta-package.zip"), "."],
      { cwd: packageDir, encoding: "utf8" }
    );
    if (zip.error || zip.status !== 0)
      throw new Error("Failed to package the delta metadata zip");
    if (
      !e.SALESFORCE_AUTH_URL ||
      !/^00D[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?$/.test(e.EXPECTED_ORG_ID || "")
    )
      throw new Error(
        "Salesforce authentication secret or expected Org ID is missing"
      );
    authFile = path.join(e.RUNNER_TEMP, `sf-auth-${e.GITHUB_RUN_ID}.txt`);
    fs.writeFileSync(authFile, e.SALESFORCE_AUTH_URL, { mode: 0o600 });
    const alias = `AXON_${e.TARGET_ENV}`;
    command("sf", [
      "org",
      "login",
      "sfdx-url",
      "--sfdx-url-file",
      authFile,
      "--alias",
      alias,
      "--json"
    ]);
    fs.unlinkSync(authFile);
    authFile = null;
    const org = JSON.parse(
      command("sf", ["org", "display", "--target-org", alias, "--json"])
    );
    if (org.result?.id !== e.EXPECTED_ORG_ID)
      throw new Error(
        "Authenticated Org ID does not match the configured target"
      );
    report.orgId = org.result.id;
    // Every environment scopes tests to what the delta actually touches instead of
    // running every local test class: any test class included in the delta itself,
    // plus anything declared in the PR's "### Apex test classes to run" code block.
    // Applies to both validate (dry-run) and deploy — same code path either way.
    // Falls back to RunLocalTests only when the delta has no Apex/trigger at all.
    const plan = testPlan(
      report.paths,
      (p) => fs.readFileSync(p, "utf8"),
      extractDeclaredTests(prBody)
    );
    const testLevel = plan.testLevel;
    const tests = plan.tests;
    report.testLevel = testLevel;
    report.tests = tests;
    const args = [
      "project",
      "deploy",
      "start",
      "--target-org",
      alias,
      "--test-level",
      testLevel,
      "--wait",
      "60",
      "--json"
    ];
    for (const t of tests) args.push("--tests", t);
    // DEV PRs do a real deploy (no --dry-run) so devs can visually validate the
    // org before approving the merge. UAT and PROD PRs keep --dry-run to avoid
    // unintended side-effects before the merge is confirmed.
    if (e.OPERATION === "validate" && e.TARGET_ENV !== "DEV")
      args.push("--dry-run");
    for (const file of report.paths) args.push("--source-dir", file);
    let result = spawnSync("sf", args, {
      encoding: "utf8",
      maxBuffer: 40 * 1024 * 1024
    });
    let payload;
    try {
      payload = JSON.parse(result.stdout);
    } catch {
      throw new Error("Salesforce returned no valid deployment JSON");
    }
    if (
      payload.result?.done === false &&
      /^0Af[a-zA-Z0-9]+$/.test(payload.result?.id || "")
    ) {
      result = spawnSync(
        "sf",
        [
          "project",
          "deploy",
          "resume",
          "--target-org",
          alias,
          "--job-id",
          payload.result.id,
          "--wait",
          "60",
          "--json"
        ],
        { encoding: "utf8", maxBuffer: 40 * 1024 * 1024 }
      );
      try {
        payload = JSON.parse(result.stdout);
      } catch {
        throw new Error("Salesforce resume returned no valid JSON");
      }
    }
    report.salesforce = safeResult(payload);
    if (!completed(payload, result.status))
      throw new Error(
        "Salesforce operation failed or has not reached a successful terminal state; inspect the evidence"
      );
    report.outcome = "Succeeded";
  } catch (error) {
    report.error = error.message;
    process.exitCode = 1;
  } finally {
    if (authFile && fs.existsSync(authFile)) fs.unlinkSync(authFile);
    fs.writeFileSync(
      path.join(directory, "result.json"),
      JSON.stringify(report, null, 2) + "\n"
    );
    const markdown = (value) =>
      String(value ?? "")
        .replace(/[<>`]/g, "")
        .replace(/[\r\n]/g, " ");
    const details = [
      ...(report.salesforce?.componentFailures || []).map(
        (f) =>
          `- ${markdown(f.component)} (${markdown(f.file)}:${f.line || "-"}): ${markdown(f.problem)}`
      ),
      ...(report.salesforce?.testFailures || []).map(
        (f) => `- ${markdown(f.test)}: ${markdown(f.message)}`
      )
    ].slice(0, 15);
    const text = [
      `## Salesforce ${report.operation}: ${report.environment}`,
      "",
      `**Result:** ${report.outcome}`,
      `**Commit:** \`${report.sha}\``,
      `**Base:** \`${report.base || "Not required / not configured"}\``,
      `**Metadata paths:** ${report.paths.length}`,
      `**Test level:** ${report.testLevel || "N/A"}${report.tests?.length ? ` (${report.tests.join(", ")})` : ""}`,
      `**Deployment ID:** ${report.salesforce?.id || "None"}`,
      `**Tests completed / failed:** ${report.salesforce?.numberTestsCompleted ?? 0} / ${report.salesforce?.numberTestErrors ?? 0}`,
      report.error || "",
      "",
      ...details,
      "",
      "See result.json and source-paths.txt in the evidence artifact for component and test failures."
    ].join("\n");
    fs.writeFileSync(path.join(directory, "summary.md"), text + "\n");
    if (e.GITHUB_STEP_SUMMARY)
      fs.appendFileSync(e.GITHUB_STEP_SUMMARY, text + "\n");

    const escapeHtml = (value) =>
      String(value ?? "").replace(
        /[&<>"']/g,
        (c) =>
          ({
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;"
          })[c]
      );
    const table = (title, items, cols) =>
      items.length
        ? `<h3>${escapeHtml(title)}</h3><table><thead><tr>${cols
            .map((c) => `<th>${escapeHtml(c)}</th>`)
            .join("")}</tr></thead><tbody>${items
            .map(
              (row) =>
                `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join("")}</tr>`
            )
            .join("")}</tbody></table>`
        : "";
    const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Salesforce ${escapeHtml(report.operation)}: ${escapeHtml(report.environment)}</title>
<style>
body{font-family:system-ui,sans-serif;margin:2rem;color:#1a1a1a;max-width:960px}
table{border-collapse:collapse;width:100%;margin:1rem 0}
th,td{border:1px solid #ddd;padding:6px 10px;text-align:left;font-size:0.9rem;vertical-align:top}
th{background:#f4f4f4}
.badge{display:inline-block;padding:2px 10px;border-radius:12px;font-weight:600}
.ok{background:#d4f7dc;color:#116329}
.fail{background:#ffd7d5;color:#82071e}
code{background:#f4f4f4;padding:1px 4px;border-radius:3px}
</style>
</head>
<body>
<h1>Salesforce ${escapeHtml(report.operation)}: ${escapeHtml(report.environment)}</h1>
<p><span class="badge ${report.outcome === "Succeeded" ? "ok" : "fail"}">${escapeHtml(report.outcome)}</span></p>
<ul>
<li><strong>Commit (to):</strong> <code>${escapeHtml(report.sha)}</code></li>
<li><strong>Base (from):</strong> <code>${escapeHtml(report.base || "Not required / not configured")}</code></li>
<li><strong>Metadata paths:</strong> ${report.paths.length}</li>
<li><strong>Test level:</strong> ${escapeHtml(report.testLevel || "N/A")}${report.tests?.length ? ` (${escapeHtml(report.tests.join(", "))})` : ""}</li>
<li><strong>Deployment ID:</strong> ${escapeHtml(report.salesforce?.id || "None")}</li>
<li><strong>Tests completed / failed:</strong> ${report.salesforce?.numberTestsCompleted ?? 0} / ${report.salesforce?.numberTestErrors ?? 0}</li>
${report.error ? `<li><strong>Error:</strong> ${escapeHtml(report.error)}</li>` : ""}
</ul>
${table(
  "Component failures",
  (report.salesforce?.componentFailures || []).map((f) => [
    f.component,
    f.file,
    f.line ?? "-",
    f.problem
  ]),
  ["Component", "File", "Line", "Problem"]
)}
${table(
  "Test failures",
  (report.salesforce?.testFailures || []).map((f) => [f.test, f.message]),
  ["Test", "Message"]
)}
${
  report.paths.length
    ? `<h3>Metadata paths (${report.paths.length})</h3><ul>${report.paths
        .map((p) => `<li><code>${escapeHtml(p)}</code></li>`)
        .join("")}</ul>`
    : ""
}
</body>
</html>
`;
    fs.writeFileSync(path.join(directory, "result.html"), html);

    // Kept short: the full component/test failure detail lives in result.json
    // and result.html inside the evidence artifact, not inline in the PR comment.
    const shortSummary = [
      `## Salesforce ${report.operation}: ${report.environment}`,
      "",
      `**Result:** ${report.outcome}`,
      `**Commit (to):** \`${report.sha}\``,
      `**Base (from):** \`${report.base || "Not required / not configured"}\``,
      `**Metadata paths:** ${report.paths.length}`,
      `**Test level:** ${report.testLevel || "N/A"}${report.tests?.length ? ` (${report.tests.join(", ")})` : ""}`,
      `**Deployment ID:** ${report.salesforce?.id || "None"}`,
      `**Tests completed / failed:** ${report.salesforce?.numberTestsCompleted ?? 0} / ${report.salesforce?.numberTestErrors ?? 0}`,
      report.error || "",
      "",
      "Full component/test failure detail, the JSON result and the validated delta package zip are attached as workflow run artifacts: `result.json`, `result.html`, `delta-package.zip`."
    ].join("\n");
    if (e.GITHUB_OUTPUT) {
      const delimiter = randomUUID();
      fs.appendFileSync(
        e.GITHUB_OUTPUT,
        `summary<<${delimiter}\n${shortSummary}\n${delimiter}\n`
      );
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  await run();
