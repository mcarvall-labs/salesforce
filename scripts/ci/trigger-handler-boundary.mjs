import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

/**
 * AXF-105 architectural check: every Apex trigger must contain only context
 * dispatch and delegation to a handler class. Business rules (queries, DML,
 * validation, calculations, field changes) belong in handlers and domain
 * services. The check recognizes actual delegation (a static call whose
 * arguments are Trigger context collections) instead of a class-name-only rule.
 *
 * Accepted trigger shape (Apex keywords are case-insensitive):
 *   trigger X on Obj(before insert, ...) {
 *     if (Trigger.isBefore && Trigger.isInsert) { AXF_CLS_XHandler.m(Trigger.new); }
 *     // or: switch on Trigger.operationType { when BEFORE_INSERT { ... } }
 *   }
 * Rule: agent-docs / Agent Tooling "Mandatory trigger -> handler ->
 * business-service boundary" (axon-salesforce-change, 4-apex.md).
 */

const GUIDANCE =
  "Triggers may only dispatch on Trigger context and call one AXF_CLS_*Handler " +
  "with Trigger.new/old/newMap/oldMap (optionally cast); rules live in the handler.";
const DEFAULT_PACKAGE_DIRECTORY = path.join("force-app", "main", "default");
const CONTEXT_ARGUMENT =
  /^(?:\(\s*(?:List|Map)\s*<[^>]+>\s*\)\s*)?Trigger\.(new|old|newMap|oldMap|size|isInsert|isUpdate|isDelete|isUndelete|isBefore|isAfter|operationType)$/i;
const CONTEXT_CONDITION =
  /^[\s()!&|]*((Trigger\.(isBefore|isAfter|isInsert|isUpdate|isDelete|isUndelete)|Trigger\.operationType\s*[!=]=\s*TriggerOperation\.[A-Z_]+)[\s()!&|]*)+$/i;
const FORBIDDEN = [
  { pattern: /\[\s*SELECT\b/i, reason: "SOQL query" },
  {
    pattern: /\b(insert|update|delete|upsert|undelete|merge)\s*[A-Za-z_(]/i,
    reason: "DML statement"
  },
  { pattern: /\bDatabase\.\w+\s*\(/i, reason: "Database DML or query" },
  { pattern: /\.addError\s*\(/i, reason: "record validation" },
  { pattern: /\bTrigger\.(new|old)\s*\[/i, reason: "record indexing" },
  { pattern: /\bfor\s*\(|\bwhile\s*\(/i, reason: "record iteration" },
  { pattern: /(?<![=!<>])=(?!=)/, reason: "assignment" },
  { pattern: /\btry\s*\{|\bcatch\s*\(/i, reason: "exception handling" },
  { pattern: /\bnew\s+[A-Za-z_]\w*\s*[({]/i, reason: "object construction" }
];

// Strings first so that '//' or '/*' inside a literal cannot swallow code.
function stripComments(source) {
  return source
    .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");
}

function triggerBody(source) {
  const head = source.search(/\btrigger\s+\w+\s+on\b/i);
  if (head < 0) {
    return null;
  }
  const start = source.indexOf("{", head);
  const end = source.lastIndexOf("}");
  if (start < 0 || end <= start) {
    return null;
  }
  return source.slice(start + 1, end);
}

function splitStatements(body) {
  const statements = [];
  let depth = 0;
  let current = "";
  for (const character of body) {
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
    current += character;
    if (character === ";" && depth === 0) {
      statements.push(current.trim());
      current = "";
    }
  }
  if (current.trim()) {
    statements.push(current.trim());
  }
  return { statements, balanced: depth === 0 };
}

function stripDispatch(body) {
  let text = body;
  let changed = true;
  while (changed) {
    changed = false;
    text = text.replace(/\bif\s*\(([^{}]*?)\)\s*\{/gi, (match, condition) => {
      if (CONTEXT_CONDITION.test(condition.trim())) {
        changed = true;
        return "{";
      }
      return match;
    });
    text = text.replace(/\bswitch\s+on\s+Trigger\.operationType\s*\{/gi, () => {
      changed = true;
      return "{";
    });
    // `when else {` must be consumed before the plain `else {` rule below.
    text = text.replace(
      /\bwhen\s+(?:else|[A-Z_]+(?:\s*,\s*[A-Z_]+)*)\s*\{/gi,
      () => {
        changed = true;
        return "{";
      }
    );
    text = text.replace(/\belse\s*\{/gi, () => {
      changed = true;
      return "{";
    });
  }
  return text.replace(/[{}]/g, " ");
}

export function delegations(statement) {
  const match = statement.match(
    /^([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(([\s\S]*)\)\s*;$/
  );
  if (!match) {
    return null;
  }
  const [, handlerClass, method, argumentList] = match;
  const args = argumentList
    .split(/,(?![^<]*>)/)
    .map((argument) => argument.trim())
    .filter(Boolean);
  if (
    args.length === 0 ||
    !args.every((argument) => CONTEXT_ARGUMENT.test(argument))
  ) {
    return null;
  }
  return { handlerClass, method, args };
}

export function analyzeTrigger(name, source, classExists) {
  const violations = [];
  const clean = stripComments(source);
  const body = triggerBody(clean);
  if (body === null) {
    return [`${name}: unable to locate trigger body`];
  }
  for (const { pattern, reason } of FORBIDDEN) {
    if (pattern.test(body)) {
      violations.push(`${name}: ${reason} found inside the trigger`);
    }
  }
  const handlers = new Set();
  const { statements, balanced } = splitStatements(stripDispatch(body));
  if (!balanced) {
    violations.push(`${name}: unbalanced parentheses in the trigger body`);
  }
  if (statements.length === 0) {
    violations.push(`${name}: no handler delegation found`);
  }
  for (const statement of statements) {
    const delegation = delegations(statement);
    if (!delegation) {
      violations.push(
        `${name}: statement is not a handler delegation -> ${statement.replace(/\s+/g, " ")}`
      );
      continue;
    }
    handlers.add(delegation.handlerClass);
  }
  for (const handlerClass of handlers) {
    if (!/^AXF_CLS_\w*Handler$/.test(handlerClass)) {
      violations.push(
        `${name}: ${handlerClass} is not an AXF_CLS_*Handler class`
      );
    } else if (!classExists(handlerClass)) {
      violations.push(`${name}: handler class ${handlerClass} does not exist`);
    }
  }
  if (handlers.size > 1) {
    violations.push(
      `${name}: delegates to more than one handler (${[...handlers].join(", ")})`
    );
  }
  return violations;
}

export function packageDirectories(root) {
  const projectFile = path.join(root, "sfdx-project.json");
  if (!fs.existsSync(projectFile)) {
    return [DEFAULT_PACKAGE_DIRECTORY];
  }
  try {
    const project = JSON.parse(fs.readFileSync(projectFile, "utf8"));
    const directories = (project.packageDirectories ?? [])
      .map((entry) => entry && entry.path)
      .filter((entry) => typeof entry === "string" && entry.trim());
    return directories.length
      ? directories.map((entry) => path.join(entry, "main", "default"))
      : [DEFAULT_PACKAGE_DIRECTORY];
  } catch {
    return [DEFAULT_PACKAGE_DIRECTORY];
  }
}

export function analyzeRepository(root = process.cwd()) {
  const directories = packageDirectories(root);
  const classDirectories = directories.map((directory) =>
    path.join(root, directory, "classes")
  );
  const classExists = (className) =>
    classDirectories.some((directory) =>
      fs.existsSync(path.join(directory, `${className}.cls`))
    );
  const objects = new Map();
  const violations = [];
  let triggers = 0;
  for (const directory of directories) {
    const triggerDirectory = path.join(root, directory, "triggers");
    const files = fs.existsSync(triggerDirectory)
      ? fs
          .readdirSync(triggerDirectory)
          .filter((file) => file.endsWith(".trigger"))
      : [];
    triggers += files.length;
    for (const file of files) {
      const source = fs.readFileSync(path.join(triggerDirectory, file), "utf8");
      const name = file.replace(/\.trigger$/, "");
      violations.push(...analyzeTrigger(name, source, classExists));
      const objectMatch = stripComments(source).match(
        /\btrigger\s+\w+\s+on\s+([\w.]+)/i
      );
      if (objectMatch) {
        const key = objectMatch[1].toLowerCase();
        const list = objects.get(key) ?? [];
        list.push(name);
        objects.set(key, list);
      }
    }
  }
  for (const [object, names] of objects) {
    if (names.length > 1) {
      violations.push(`${object}: more than one trigger (${names.join(", ")})`);
    }
  }
  return { triggers, violations };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const { triggers, violations } = analyzeRepository();
  if (violations.length) {
    console.error(`Trigger handler boundary violated (${violations.length}):`);
    for (const violation of violations) {
      console.error(` - ${violation}`);
    }
    console.error(GUIDANCE);
    process.exit(1);
  }
  if (triggers === 0) {
    console.error(
      "Trigger handler boundary: no trigger found under the package directories; refusing to pass vacuously."
    );
    process.exit(1);
  }
  console.log(`Trigger handler boundary verified for ${triggers} trigger(s).`);
}
