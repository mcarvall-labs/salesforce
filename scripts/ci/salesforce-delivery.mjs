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

export function completed(payload, exitCode) {
  return (
    exitCode === 0 &&
    payload.status === 0 &&
    payload.result?.done === true &&
    payload.result?.success === true &&
    payload.result?.status === "Succeeded"
  );
}

export function selectBaseline(runs, currentRunId, initialBase) {
  const previous = runs
    .filter(
      (r) => String(r.id) !== String(currentRunId) && r.conclusion === "success"
    )
    .sort((a, b) => b.run_number - a.run_number)[0];
  const base = previous?.head_sha || initialBase;
  if (!/^[0-9a-f]{40}$/.test(base || "")) {
    throw new Error(
      "Set SALESFORCE_BASE_SHA to the verified initial org baseline before the first metadata operation"
    );
  }
  return base;
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
    if (e.OPERATION === "deploy") {
      const prs = JSON.parse(
        command("gh", [
          "api",
          `repos/${e.GITHUB_REPOSITORY}/commits/${e.GITHUB_SHA}/pulls`
        ])
      );
      if (
        !prs.some(
          (pr) =>
            pr.merged_at &&
            pr.base.ref === branch &&
            pr.merge_commit_sha === e.GITHUB_SHA
        )
      )
        throw new Error(
          "Deploy requires a merged pull request for this exact commit"
        );
    }

    // A configuration-only PR needs neither org credentials nor a baseline.
    if (
      e.OPERATION === "validate" &&
      changes(e.PR_BASE_SHA, e.GITHUB_SHA).length === 0
    ) {
      report.outcome = "No metadata changes";
      return;
    }
    let runs = [];
    const response = spawnSync(
      "gh",
      [
        "api",
        `repos/${e.GITHUB_REPOSITORY}/actions/workflows/deploy-salesforce.yml/runs?branch=${branch}&event=push&status=success&per_page=100`
      ],
      { encoding: "utf8" }
    );
    if (response.status === 0) runs = JSON.parse(response.stdout).workflow_runs;
    else if (!response.stderr?.includes("404"))
      throw new Error("Cannot read deployment history");
    const base = selectBaseline(runs, e.GITHUB_RUN_ID, e.INITIAL_BASE_SHA);
    command("git", ["merge-base", "--is-ancestor", base, e.GITHUB_SHA]);
    report.base = base;
    report.paths = sourcePaths(changes(base, e.GITHUB_SHA));
    fs.writeFileSync(
      path.join(directory, "source-paths.txt"),
      report.paths.join("\n") + "\n"
    );
    if (!report.paths.length) {
      report.outcome = "No metadata changes";
      return;
    }
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
    const testLevel = e.TARGET_ENV === "DEV" ? "NoTestRun" : "RunLocalTests";
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
    if (e.OPERATION === "validate") args.push("--dry-run");
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
    if (e.GITHUB_OUTPUT) {
      const delimiter = randomUUID();
      fs.appendFileSync(
        e.GITHUB_OUTPUT,
        `summary<<${delimiter}\n${text.slice(0, 12000)}\n${delimiter}\n`
      );
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  await run();
