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
const success =
  Number(payload.status) === 0 &&
  result.success !== false &&
  result.status !== "Failed";
const message = payload.message || result.errorMessage || result.message || "";

for (const failure of failures) {
  const fields = [];
  if (failure.file) fields.push(`file=${encode(failure.file)}`);
  if (failure.line) fields.push(`line=${failure.line}`);
  if (failure.column) fields.push(`col=${failure.column}`);
  console.log(
    `::error ${fields.join(",")}::${encode(`${failure.component}: ${failure.message}`)}`
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
if (process.env.GITHUB_STEP_SUMMARY)
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${summary.join("\n")}\n`);
console.log(summary.join("\n"));

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
