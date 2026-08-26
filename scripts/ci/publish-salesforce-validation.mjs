import fs from "node:fs";

const inputPath = process.argv[2];
if (!inputPath) process.exit(2);
const raw = fs.readFileSync(inputPath, "utf8");
let payload;
try {
  payload = JSON.parse(raw);
} catch {
  payload = { status: 1, message: "Salesforce CLI did not return valid JSON." };
}

const result = payload.result || {};
const values = result.details?.componentFailures;
const failures = (
  values ? (Array.isArray(values) ? values : [values]) : []
).map((item) => ({
  component: `${item.componentType || item.type || "Unknown"}: ${item.fullName || item.componentName || "Unknown"}`,
  file: item.fileName || item.filePath || "",
  line: item.lineNumber || "",
  column: item.columnNumber || "",
  message:
    item.problem || item.error || item.message || "Unknown validation error"
}));
const testValues = result.details?.runTestResult?.failures;
const testFailures = (
  testValues ? (Array.isArray(testValues) ? testValues : [testValues]) : []
).map((item) => ({
  test: `${item.name || "Unknown"}.${item.methodName || "Unknown"}`,
  message: item.message || "Unknown test failure",
  stackTrace: item.stackTrace || ""
}));
const success =
  Number(payload.status) === 0 &&
  result.success !== false &&
  result.status !== "Failed";
const message = payload.message || result.errorMessage || result.message || "";
const environment = process.env.SALESFORCE_ENVIRONMENT || "DEV";
const operation = process.env.SALESFORCE_OPERATION || "Dry-run validation";
const artifactName = process.env.SALESFORCE_ARTIFACT_NAME || "Not uploaded";
const testLevel = process.env.SALESFORCE_TEST_LEVEL || "Unknown";
const orgId = process.env.SALESFORCE_ORG_ID || "Unknown";
const sha = process.env.GITHUB_SHA || "Unknown";
const jobUrl =
  process.env.GITHUB_SERVER_URL &&
  process.env.GITHUB_REPOSITORY &&
  process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : "";
const componentCount =
  result.numberComponentsTotal ?? result.numberComponentsDeployed ?? "Unknown";
const testsCompleted = result.numberTestsCompleted ?? 0;
const testsTotal = result.numberTestsTotal ?? 0;
const testErrors = result.numberTestErrors ?? 0;
const testsResult =
  testsTotal === 0 && testsCompleted === 0
    ? `Not run (\`${md(testLevel)}\`)`
    : `${testsCompleted}/${testsTotal} completed, ${testErrors} failed`;

for (const failure of failures) {
  const fields = [];
  if (failure.file) fields.push(`file=${encode(failure.file)}`);
  if (failure.line) fields.push(`line=${failure.line}`);
  if (failure.column) fields.push(`col=${failure.column}`);
  console.log(
    `::error ${fields.join(",")}::${encode(`${failure.component}: ${failure.message}`)}`
  );
}
for (const failure of testFailures) {
  console.log(
    `::error::${encode(`${failure.test}: ${failure.message}${failure.stackTrace ? ` (${failure.stackTrace})` : ""}`)}`
  );
}
if (!success && !failures.length)
  console.log(
    `::error::${encode(message || "Salesforce validation failed without component details.")}`
  );

const summary = [
  "## Salesforce validation",
  "",
  `**Result:** ${success ? "✅ Passed" : "❌ Failed"}`,
  result.id ? `**Deployment ID:** \`${result.id}\`` : "",
  ""
].filter(Boolean);
if (failures.length) {
  summary.push("| Component | File | Location | Error |", "|---|---|---:|---|");
  for (const failure of failures) {
    const location = failure.line
      ? `${failure.line}${failure.column ? `:${failure.column}` : ""}`
      : "-";
    summary.push(
      `| ${md(failure.component)} | ${md(failure.file || "-")} | ${location} | ${md(failure.message)} |`
    );
  }
} else
  summary.push(
    message
      ? `**Message:** ${md(message)}`
      : "No component errors were returned."
  );
if (testFailures.length) {
  summary.push("", "### Test failures", "");
  for (const failure of testFailures)
    summary.push(
      `- **${md(failure.test)}:** ${md(failure.message)}${failure.stackTrace ? `<br>${md(failure.stackTrace)}` : ""}`
    );
}
if (process.env.GITHUB_STEP_SUMMARY)
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${summary.join("\n")}\n`);
console.log(summary.join("\n"));

const comment = [
  "<!-- axon-salesforce-validation -->",
  `## Salesforce ${md(operation)}`,
  "",
  `**Result:** ${success ? "✅ Passed" : "❌ Failed"}`,
  "",
  "| Evidence | Value |",
  "|---|---|",
  `| Environment | ${md(environment)} |`,
  `| Org ID | \`${md(orgId)}\` |`,
  `| Deployment ID | ${result.id ? `\`${md(result.id)}\`` : "Not returned"} |`,
  `| Components | ${md(componentCount)} |`,
  `| Tests | ${md(testsResult)} |`,
  `| Raw artifact | \`${md(artifactName)}\` (available in the workflow run) |`,
  `| Validated SHA | \`${md(sha)}\` |`,
  `| Workflow job | ${jobUrl ? `[Open run](${jobUrl})` : "Unavailable"} |`,
  ""
];
if (failures.length) {
  comment.push("### Component failures", "");
  comment.push("| Component | File | Location | Error |", "|---|---|---:|---|");
  for (const failure of failures) {
    const location = failure.line
      ? `${failure.line}${failure.column ? `:${failure.column}` : ""}`
      : "-";
    comment.push(
      `| ${md(failure.component)} | ${md(failure.file || "-")} | ${location} | ${md(failure.message)} |`
    );
  }
  comment.push("");
} else if (message) {
  comment.push(`**Salesforce message:** ${md(message)}`, "");
}
if (testFailures.length) {
  comment.push("### Test failures", "");
  for (const failure of testFailures)
    comment.push(
      `- **${md(failure.test)}:** ${md(failure.message)}${failure.stackTrace ? `<br>${md(failure.stackTrace)}` : ""}`
    );
  comment.push("");
}
comment.push(
  `_Updated by workflow run ${process.env.GITHUB_RUN_NUMBER || "unknown"}. This comment is replaced on each execution._`
);
fs.writeFileSync("salesforce-validation-comment.md", `${comment.join("\n")}\n`);

function encode(value) {
  return String(value)
    .replaceAll("%", "%25")
    .replaceAll("\r", "%0D")
    .replaceAll("\n", "%0A");
}
function md(value) {
  return String(value)
    .replaceAll("|", "\\|")
    .replaceAll("\r", " ")
    .replaceAll("\n", "<br>");
}
