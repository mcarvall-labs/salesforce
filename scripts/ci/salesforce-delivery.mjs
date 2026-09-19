import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

export function sourcePaths(entries) {
  const paths = new Set();
  for (const { status, file } of entries) {
    // Deletions are handled separately by buildDestructiveChangesXml; they
    // never enter the additive/modified source-dir list used for deployment.
    if (status === "D") continue;
    if (!file.startsWith("force-app/") || /[\r\n]/.test(file))
      throw new Error("Invalid metadata path");
    const bundle = file.match(/^(force-app\/.*\/(?:aura|lwc)\/[^/]+)\//);
    paths.add(bundle ? bundle[1] : file);
  }
  return [...paths].sort();
}

// Metadata types deletable from a single top-level force-app folder, matched
// against the path with the "force-app/main/default/<folder>/" prefix
// stripped. The capture group is the metadata member (fullName). Deliberately
// scoped to the metadata types this project actually uses (see force-app/main/default);
// anything else — including lwc/aura bundles, whose member depends on whether
// the WHOLE bundle or only some files were deleted — is left unresolved for
// manual review rather than guessed at.
const TOP_LEVEL_DESTRUCTIVE_TYPES = {
  applications: ["CustomApplication", /^([^/]+)\.app-meta\.xml$/],
  classes: ["ApexClass", /^([^/]+)\.cls(?:-meta\.xml)?$/],
  contentassets: ["ContentAsset", /^([^/]+)\.asset-meta\.xml$/],
  customMetadata: ["CustomMetadata", /^([^/]+)\.md-meta\.xml$/],
  customPermissions: [
    "CustomPermission",
    /^([^/]+)\.customPermission-meta\.xml$/
  ],
  externalCredentials: [
    "ExternalCredential",
    /^([^/]+)\.externalCredential-meta\.xml$/
  ],
  flexipages: ["FlexiPage", /^([^/]+)\.flexipage-meta\.xml$/],
  layouts: ["Layout", /^(.+)\.layout-meta\.xml$/],
  messageChannels: [
    "LightningMessageChannel",
    /^([^/]+)\.messageChannel-meta\.xml$/
  ],
  namedCredentials: ["NamedCredential", /^([^/]+)\.namedCredential-meta\.xml$/],
  notificationtypes: [
    "CustomNotificationType",
    /^([^/]+)\.notiftype-meta\.xml$/
  ],
  permissionsetgroups: [
    "PermissionSetGroup",
    /^([^/]+)\.permissionsetgroup-meta\.xml$/
  ],
  permissionsets: ["PermissionSet", /^([^/]+)\.permissionset-meta\.xml$/],
  profiles: ["Profile", /^([^/]+)\.profile-meta\.xml$/],
  roles: ["Role", /^([^/]+)\.role-meta\.xml$/],
  sharingRules: ["SharingRules", /^([^/]+)\.sharingRules-meta\.xml$/],
  staticresources: ["StaticResource", /^([^/]+)\.resource-meta\.xml$/],
  tabs: ["CustomTab", /^([^/]+)\.tab-meta\.xml$/],
  translations: ["Translations", /^([^/]+)\.translation-meta\.xml$/],
  triggers: ["ApexTrigger", /^([^/]+)\.trigger(?:-meta\.xml)?$/]
};

// force-app/main/default/objects/<Object>/<childFolder>/<Name>.*-meta.xml
const OBJECT_CHILD_DESTRUCTIVE_TYPES = {
  fields: "CustomField",
  validationRules: "ValidationRule",
  recordTypes: "RecordType",
  listViews: "ListView",
  webLinks: "WebLink",
  compactLayouts: "CompactLayout",
  businessProcesses: "BusinessProcess",
  fieldSets: "FieldSet",
  sharingReasons: "SharingReason"
};

export function destructiveMember(file) {
  const top = /^force-app\/main\/default\/([^/]+)\/(.+)$/.exec(file);
  if (!top) return null;
  const [, folder, rest] = top;
  if (folder === "objects") {
    const object = /^([^/]+)\/[^/]+\.object-meta\.xml$/.exec(rest);
    if (object) return { type: "CustomObject", member: object[1] };
    const child = /^([^/]+)\/([^/]+)\/([^/]+)\.[A-Za-z]+-meta\.xml$/.exec(rest);
    if (!child) return null;
    const [, objectName, childFolder, name] = child;
    const type = OBJECT_CHILD_DESTRUCTIVE_TYPES[childFolder];
    return type ? { type, member: `${objectName}.${name}` } : null;
  }
  const entry = TOP_LEVEL_DESTRUCTIVE_TYPES[folder];
  if (!entry) return null;
  const [type, pattern] = entry;
  const match = pattern.exec(rest);
  return match ? { type, member: match[1] } : null;
}

export function buildDestructiveChangesXml(deletedFiles) {
  const byType = new Map();
  const unresolved = [];
  for (const file of deletedFiles) {
    const resolved = destructiveMember(file);
    if (!resolved) {
      unresolved.push(file);
      continue;
    }
    if (!byType.has(resolved.type)) byType.set(resolved.type, new Set());
    byType.get(resolved.type).add(resolved.member);
  }
  const escapeXml = (v) =>
    String(v).replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&apos;"
        })[c]
    );
  const types = [...byType.keys()].sort();
  const body = types
    .map((type) => {
      const members = [...byType.get(type)]
        .sort()
        .map((m) => `    <members>${escapeXml(m)}</members>`)
        .join("\n");
      return `  <types>\n${members}\n    <name>${type}</name>\n  </types>`;
    })
    .join("\n");
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n` +
    (body ? `${body}\n` : "") +
    `  <version>62.0</version>\n</Package>\n`;
  return { xml, unresolved };
}

// Versioned, PR-reviewed destructive manifests. Unlike the auto-generated
// destructiveChanges.xml (evidence only, never applied), a manifest checked
// in at one of these paths IS passed straight to `sf project deploy start`
// and gets applied for real on every environment it reaches as the file
// flows through the normal develop -> uat -> main promotion. Committing (and
// merging via PR review) the file IS the "explicitly approved destructive
// release" the fail-closed default otherwise requires manually, off-pipeline.
// Empty by default (no <types> entries) so its mere presence is a no-op;
// remove or empty it again once the intended deletion has been applied.
export const DESTRUCTIVE_MANIFEST_PATHS = [
  ["--pre-destructive-changes", "manifest/destructiveChangesPre.xml"],
  ["--post-destructive-changes", "manifest/destructiveChangesPost.xml"]
];

export function destructiveManifestArgs(exists, readFile) {
  const args = [];
  const applied = [];
  for (const [flag, file] of DESTRUCTIVE_MANIFEST_PATHS) {
    if (!exists(file)) continue;
    if (!/<types>/.test(readFile(file))) continue;
    args.push(flag, file);
    applied.push(file);
  }
  return { args, applied };
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
    // Apex class names are PascalCase by convention; requiring an uppercase
    // first letter rejects prose accidentally typed into the block (e.g. a
    // sentence like "the remaining seven classes...") instead of class names.
    if (/^[A-Z][A-Za-z0-9_]*$/.test(name)) names.push(name);
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
    const entries = changes(baseSha, e.GITHUB_SHA);
    report.paths = sourcePaths(entries);
    fs.writeFileSync(
      path.join(directory, "source-paths.txt"),
      report.paths.join("\n") + "\n"
    );
    const deletedFiles = [
      ...new Set(entries.filter((en) => en.status === "D").map((en) => en.file))
    ].sort();
    report.deletedPaths = deletedFiles;
    if (deletedFiles.length) {
      // Deletions never auto-deploy: generate the destructive manifest as
      // evidence for a human to review and apply separately (see
      // docs/SALESFORCE_DELIVERY.md). The additive/modified delta below still
      // validates/deploys normally when present.
      const { xml, unresolved } = buildDestructiveChangesXml(deletedFiles);
      fs.writeFileSync(path.join(directory, "destructiveChanges.xml"), xml);
      fs.writeFileSync(
        path.join(directory, "package.xml"),
        '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n  <version>62.0</version>\n</Package>\n'
      );
      report.destructiveUnresolved = unresolved;
    }
    // A versioned manifest (manifest/destructiveChanges{Pre,Post}.xml, checked
    // into the repo and reviewed via PR) is genuinely applied, unlike the
    // evidence-only destructiveChanges.xml above — so its mere presence must
    // still trigger a deploy even when this specific commit's own force-app
    // diff is empty (e.g. the PR that adds the manifest only touches manifest/).
    const manifest = destructiveManifestArgs(
      (p) => fs.existsSync(p),
      (p) => fs.readFileSync(p, "utf8")
    );
    report.versionedDestructiveManifests = manifest.applied;
    if (!report.paths.length && !manifest.applied.length) {
      report.outcome = deletedFiles.length
        ? "Destructive changes only — manual review required"
        : "No metadata changes";
      return;
    }
    // Package the exact validated/deployed delta as mdapi-format metadata so the
    // evidence artifact carries the same content submitted to Salesforce. Also
    // reused below as the --manifest package.xml when a versioned destructive
    // manifest is applied (sf requires --manifest, not --source-dir/
    // --metadata-dir, alongside --pre/post-destructive-changes). Skipped for a
    // pure versioned-manifest deploy (nothing additive to package).
    let packageDir;
    if (report.paths.length) {
      packageDir = path.join(
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
    if (manifest.applied.length) {
      // `sf project deploy start` rejects --source-dir/--metadata-dir combined
      // with --pre/post-destructive-changes: it requires --manifest. Reuse the
      // package.xml already produced above for the additive delta (--manifest
      // resolves file paths from the project's own source dirs, not from
      // wherever that file happens to sit, so this works even though the file
      // lives in a converted mdapi temp dir); for a pure-destructive deploy,
      // write a fresh empty one. --ignore-warnings so deleting a component
      // that doesn't exist in this environment (expected wherever the target
      // metadata was never deployed, e.g. DEV/UAT) doesn't fail the deploy.
      let manifestPath;
      if (packageDir) {
        manifestPath = path.join(packageDir, "package.xml");
      } else {
        const emptyDir = path.join(
          e.RUNNER_TEMP,
          `empty-package-${e.GITHUB_RUN_ID}-${e.GITHUB_RUN_ATTEMPT || 1}`
        );
        fs.mkdirSync(emptyDir, { recursive: true });
        manifestPath = path.join(emptyDir, "package.xml");
        fs.writeFileSync(
          manifestPath,
          '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n  <version>62.0</version>\n</Package>\n'
        );
      }
      args.push("--manifest", manifestPath, "--ignore-warnings");
    } else if (report.paths.length) {
      for (const file of report.paths) args.push("--source-dir", file);
    }
    args.push(...manifest.args);
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
      report.deletedPaths?.length
        ? `**Deletions:** ${report.deletedPaths.length} — see destructiveChanges.xml in the evidence artifact. NOT auto-deployed; requires manual review and a separate destructive deploy.${report.destructiveUnresolved?.length ? ` ${report.destructiveUnresolved.length} deleted path(s) could not be mapped to a metadata type automatically: ${report.destructiveUnresolved.join(", ")}.` : ""}`
        : "",
      report.versionedDestructiveManifests?.length
        ? `**Versioned destructive manifest APPLIED:** ${report.versionedDestructiveManifests.join(", ")} — this was actually deployed (or dry-run validated), not just evidence.`
        : "",
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
.warn{background:#fff1c2;color:#7a5c00}
code{background:#f4f4f4;padding:1px 4px;border-radius:3px}
</style>
</head>
<body>
<h1>Salesforce ${escapeHtml(report.operation)}: ${escapeHtml(report.environment)}</h1>
<p><span class="badge ${report.outcome === "Succeeded" ? "ok" : report.outcome.includes("manual review") ? "warn" : "fail"}">${escapeHtml(report.outcome)}</span></p>
<ul>
<li><strong>Commit (to):</strong> <code>${escapeHtml(report.sha)}</code></li>
<li><strong>Base (from):</strong> <code>${escapeHtml(report.base || "Not required / not configured")}</code></li>
<li><strong>Metadata paths:</strong> ${report.paths.length}</li>
<li><strong>Test level:</strong> ${escapeHtml(report.testLevel || "N/A")}${report.tests?.length ? ` (${escapeHtml(report.tests.join(", "))})` : ""}</li>
<li><strong>Deployment ID:</strong> ${escapeHtml(report.salesforce?.id || "None")}</li>
<li><strong>Tests completed / failed:</strong> ${report.salesforce?.numberTestsCompleted ?? 0} / ${report.salesforce?.numberTestErrors ?? 0}</li>
${report.versionedDestructiveManifests?.length ? `<li><strong>Versioned destructive manifest APPLIED:</strong> ${escapeHtml(report.versionedDestructiveManifests.join(", "))} — this was actually deployed (or dry-run validated), not just evidence.</li>` : ""}
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
${
  report.deletedPaths?.length
    ? `<h3>Deletions (${report.deletedPaths.length}) — NOT auto-deployed</h3>` +
      `<p>Generated <code>destructiveChanges.xml</code>/<code>package.xml</code> in this evidence artifact. Requires manual review and a separate destructive deploy.` +
      (report.destructiveUnresolved?.length
        ? ` ${report.destructiveUnresolved.length} path(s) could not be mapped to a metadata type automatically and need fully manual triage.`
        : "") +
      `</p><ul>${report.deletedPaths
        .map(
          (p) =>
            `<li><code>${escapeHtml(p)}</code>${report.destructiveUnresolved?.includes(p) ? " — <em>unresolved</em>" : ""}</li>`
        )
        .join("")}</ul>`
    : ""
}
</body>
</html>
`;
    fs.writeFileSync(path.join(directory, "result.html"), html);

    // Structured, single-line outputs let the workflow build a compact, visual
    // PR comment (icon/badge + a few key facts) without parsing a text blob.
    // Full component/test failure detail lives only in result.json/result.html
    // inside the evidence artifact, never inline in the PR comment.
    if (e.GITHUB_OUTPUT) {
      const line = (key, value) =>
        `${key}=${String(value ?? "")
          .replace(/[\r\n]/g, " ")
          .slice(0, 300)}\n`;
      fs.appendFileSync(
        e.GITHUB_OUTPUT,
        line("outcome", report.outcome) +
          line("deploymentId", report.salesforce?.id) +
          line("componentsTotal", report.salesforce?.numberComponentsTotal) +
          line("testsCompleted", report.salesforce?.numberTestsCompleted ?? 0) +
          line("testsFailed", report.salesforce?.numberTestErrors ?? 0) +
          line("deletedCount", report.deletedPaths?.length ?? 0) +
          line(
            "versionedDestructiveApplied",
            (report.versionedDestructiveManifests?.length ?? 0) > 0
          ) +
          line("errorMessage", report.error)
      );
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  await run();
