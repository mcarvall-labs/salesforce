import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

/**
 * AXF-105 architectural check: every Apex trigger must contain only context
 * dispatch and delegation to a handler class. Business rules (queries, DML,
 * validation, calculations, field changes) belong in handlers and domain
 * services. The check recognizes actual delegation (a static call whose
 * arguments are Trigger context collections) instead of a class-name-only rule.
 */

const TRIGGER_DIRECTORY = path.join("force-app", "main", "default", "triggers");
const CLASS_DIRECTORY = path.join("force-app", "main", "default", "classes");
const CONTEXT_ARGUMENT =
  /^Trigger\.(new|old|newMap|oldMap|isInsert|isUpdate|isDelete|isUndelete|isBefore|isAfter|operationType)$/;
const CONTEXT_CONDITION =
  /^[\s()!&|]*(Trigger\.(isBefore|isAfter|isInsert|isUpdate|isDelete|isUndelete)[\s()!&|]*)+$/;
const FORBIDDEN = [
  { pattern: /\[\s*SELECT\b/i, reason: "SOQL query" },
  {
    pattern: /\b(insert|update|delete|upsert|undelete|merge)\s+[A-Za-z_(]/,
    reason: "DML statement"
  },
  { pattern: /\bDatabase\.\w+\s*\(/, reason: "Database DML or query" },
  { pattern: /\.addError\s*\(/, reason: "record validation" },
  { pattern: /\bTrigger\.(new|old)\s*\[/, reason: "record indexing" },
  { pattern: /\bfor\s*\(|\bwhile\s*\(/, reason: "record iteration" },
  { pattern: /(?<![=!<>])=(?!=)/, reason: "assignment" },
  { pattern: /\btry\s*\{|\bcatch\s*\(/, reason: "exception handling" },
  { pattern: /\bnew\s+[A-Za-z_]\w*\s*[({]/, reason: "object construction" }
];

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "")
    .replace(/'(?:[^'\\]|\\.)*'/g, "''");
}

function triggerBody(source) {
  const start = source.indexOf("{", source.search(/\btrigger\s+\w+\s+on\b/));
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
  return statements;
}

function stripDispatch(body) {
  let text = body;
  let changed = true;
  while (changed) {
    changed = false;
    text = text.replace(/\bif\s*\(([^{}]*?)\)\s*\{/g, (match, condition) => {
      if (CONTEXT_CONDITION.test(condition.trim())) {
        changed = true;
        return "{";
      }
      return match;
    });
    text = text.replace(/\belse\s*\{/g, () => {
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
    .split(",")
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
  const statements = splitStatements(stripDispatch(body));
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

export function analyzeRepository(root = process.cwd()) {
  const triggerDirectory = path.join(root, TRIGGER_DIRECTORY);
  const classDirectory = path.join(root, CLASS_DIRECTORY);
  const classExists = (className) =>
    fs.existsSync(path.join(classDirectory, `${className}.cls`));
  const objects = new Map();
  const violations = [];
  const triggers = fs.existsSync(triggerDirectory)
    ? fs
        .readdirSync(triggerDirectory)
        .filter((file) => file.endsWith(".trigger"))
    : [];
  for (const file of triggers) {
    const source = fs.readFileSync(path.join(triggerDirectory, file), "utf8");
    const name = file.replace(/\.trigger$/, "");
    violations.push(...analyzeTrigger(name, source, classExists));
    const objectMatch = stripComments(source).match(
      /\btrigger\s+\w+\s+on\s+([\w.]+)/
    );
    if (objectMatch) {
      const list = objects.get(objectMatch[1]) ?? [];
      list.push(name);
      objects.set(objectMatch[1], list);
    }
  }
  for (const [object, names] of objects) {
    if (names.length > 1) {
      violations.push(`${object}: more than one trigger (${names.join(", ")})`);
    }
  }
  return { triggers: triggers.length, violations };
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
    process.exit(1);
  }
  console.log(`Trigger handler boundary verified for ${triggers} trigger(s).`);
}
