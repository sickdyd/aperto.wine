"use strict";

/**
 * Dependency-vulnerability gate for the Expo client.
 *
 * Runs `npm audit --json`, refuses anything at moderate or above that is not
 * accounted for in audit-allowlist.jsonc, and — the part that matters — refuses
 * to reach a verdict at all from a report it does not fully recognise.
 *
 * That last property is why this is hand-rolled rather than audit-ci. audit-ci
 * treats an unreadable audit as an empty one: hand it a report in a schema it
 * does not know, or an npm that errored out entirely, and it prints "Passed npm
 * security audit" and exits 0. A gate that evaporates on a green check is worse
 * than no gate, because the check asserts a safety nobody is checking. Every
 * unexpected condition here is an error instead.
 *
 * Dev dependencies are deliberately in scope: `npm audit` includes them by
 * default and Expo's entire build toolchain is devDependency-shaped, so
 * excluding them would exclude almost everything worth seeing.
 */

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// Ascending, so an index comparison answers "at or above the threshold".
const SEVERITIES = ["info", "low", "moderate", "high", "critical"];

// npm stamps its audit output with a format version. Pinning it is what turns
// "npm reshaped its report" from a silent pass into a loud failure.
const SUPPORTED_REPORT_VERSION = 2;

const ADVISORY_URL = /\/advisories\/(GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4})\b/;
const ADVISORY_ID = /^GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}$/;

/** Raised for every condition that must stop the gate rather than pass it. */
class AuditGateError extends Error {}

/**
 * Reads the jsonc allowlist. Comments are what make the file self-documenting,
 * so only whole-line ones are stripped — a `//` inside a JSON string survives.
 *
 * @param {string} file
 */
function readConfig(file) {
  const source = fs.readFileSync(file, "utf8");
  const config = JSON.parse(
    source
      .split("\n")
      .filter((line) => !/^\s*\/\//.test(line))
      .join("\n"),
  );

  if (!SEVERITIES.includes(config.failOnSeverity)) {
    throw new AuditGateError(
      `${path.basename(file)}: failOnSeverity must be one of ${SEVERITIES.join(", ")}, got ${JSON.stringify(config.failOnSeverity)}`,
    );
  }
  if (!Array.isArray(config.allowlist)) {
    throw new AuditGateError(`${path.basename(file)}: allowlist must be an array`);
  }

  // A bare package name would suppress every present and future advisory
  // against that package. Only a specific advisory is a triage decision.
  for (const entry of config.allowlist) {
    if (typeof entry !== "string" || !ADVISORY_ID.test(entry)) {
      throw new AuditGateError(
        `${path.basename(file)}: ${JSON.stringify(entry)} is not a GitHub advisory id`,
      );
    }
  }

  return config;
}

/**
 * Turns npm's stdout into a report, refusing anything it cannot vouch for.
 *
 * @param {string} stdout
 * @param {number | null} status npm's exit code, or null if it was signalled
 */
function parseReport(stdout, status) {
  // `npm audit` exits 1 when it finds something and 0 when it does not. Any
  // other code is npm failing rather than reporting, and a failure to run is
  // not evidence of a clean tree.
  if (status !== 0 && status !== 1) {
    throw new AuditGateError(
      `npm audit exited with ${status === null ? "a signal" : `code ${status}`} — it did not complete, so nothing can be concluded from it`,
    );
  }
  if (stdout.trim() === "") {
    throw new AuditGateError("npm audit produced no output");
  }

  let report;
  try {
    report = JSON.parse(stdout);
  } catch (error) {
    throw new AuditGateError(`npm audit did not produce JSON: ${error.message}`);
  }

  if (report === null || typeof report !== "object" || Array.isArray(report)) {
    throw new AuditGateError("npm audit returned JSON that is not a report object");
  }
  if (report.auditReportVersion !== SUPPORTED_REPORT_VERSION) {
    throw new AuditGateError(
      `npm audit reported format version ${JSON.stringify(report.auditReportVersion)}, ` +
        `but this gate only understands version ${SUPPORTED_REPORT_VERSION}. ` +
        "Update scripts/audit.js to the new format — do not assume the tree is clean.",
    );
  }
  if (
    report.vulnerabilities === null ||
    typeof report.vulnerabilities !== "object" ||
    Array.isArray(report.vulnerabilities)
  ) {
    throw new AuditGateError("npm audit report has no vulnerabilities object");
  }

  const counts = report.metadata && report.metadata.vulnerabilities;
  if (counts === null || typeof counts !== "object") {
    throw new AuditGateError("npm audit report has no metadata.vulnerabilities counts");
  }
  for (const severity of SEVERITIES) {
    if (typeof counts[severity] !== "number") {
      throw new AuditGateError(
        `npm audit report is missing a numeric ${severity} count — the report is not the shape this gate reads`,
      );
    }
  }

  return report;
}

/**
 * Collects the distinct advisories behind the report. npm nests each finding
 * under every package it propagates through; the advisory itself only appears
 * as an object in a `via` array.
 *
 * @param {{ vulnerabilities: Record<string, any> }} report
 * @returns {Map<string, { severity: string, packages: Set<string> }>}
 */
function collectAdvisories(report) {
  const advisories = new Map();

  for (const entry of Object.values(report.vulnerabilities)) {
    for (const via of entry.via || []) {
      // A string `via` is another vulnerable package, not an advisory.
      if (typeof via === "string") continue;

      const matched = ADVISORY_URL.exec(String(via.url || ""));
      if (!matched) {
        throw new AuditGateError(
          `npm reported an advisory this gate cannot identify (${JSON.stringify(via.title || via.url || via)}). ` +
            "An advisory with no id cannot be triaged or allowlisted.",
        );
      }
      if (!SEVERITIES.includes(via.severity)) {
        throw new AuditGateError(
          `advisory ${matched[1]} has an unrecognised severity ${JSON.stringify(via.severity)}`,
        );
      }

      const existing = advisories.get(matched[1]);
      if (existing) {
        existing.packages.add(via.name);
      } else {
        advisories.set(matched[1], { severity: via.severity, packages: new Set([via.name]) });
      }
    }
  }

  return advisories;
}

/**
 * @param {Map<string, { severity: string, packages: Set<string> }>} advisories
 * @param {{ failOnSeverity: string, allowlist: string[] }} config
 */
function evaluate(advisories, config) {
  const threshold = SEVERITIES.indexOf(config.failOnSeverity);

  const unexpected = [...advisories]
    .filter(([id, { severity }]) => !config.allowlist.includes(id) && SEVERITIES.indexOf(severity) >= threshold)
    .map(([id, { severity, packages }]) => ({ id, severity, packages: [...packages] }));

  // An allowlist entry that matches nothing is either an accepted advisory that
  // upstream has finally fixed — delete it — or a sign the report never
  // contained what we expected. Both need a human, and the second is the one
  // that would otherwise let this gate quietly stop gating anything.
  const stale = config.allowlist.filter((id) => !advisories.has(id));

  return { unexpected, stale };
}

function main() {
  const directory = path.resolve(__dirname, "..");
  const config = readConfig(path.join(directory, "audit-allowlist.jsonc"));

  const npm = spawnSync("npm", ["audit", "--json"], {
    cwd: directory,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (npm.error) {
    throw new AuditGateError(`could not run npm audit: ${npm.error.message}`);
  }

  const advisories = collectAdvisories(parseReport(npm.stdout, npm.status));
  const { unexpected, stale } = evaluate(advisories, config);

  for (const { id, severity, packages } of unexpected) {
    console.error(`✗ ${severity} ${id} (${packages.join(", ")}) — https://github.com/advisories/${id}`);
  }
  for (const id of stale) {
    console.error(
      `✗ ${id} is allowlisted but npm audit no longer reports it. If it was fixed upstream, ` +
        "delete the entry and its comment from audit-allowlist.jsonc.",
    );
  }
  if (unexpected.length > 0 || stale.length > 0) {
    console.error(
      `\n${unexpected.length} unaccounted-for advisor${unexpected.length === 1 ? "y" : "ies"} ` +
        `at ${config.failOnSeverity} or above, ${stale.length} stale allowlist entr${stale.length === 1 ? "y" : "ies"}.`,
    );
    process.exit(1);
  }

  console.log(
    `✓ no advisories at ${config.failOnSeverity} or above beyond the ${config.allowlist.length} ` +
      `accounted for in audit-allowlist.jsonc: ${config.allowlist.join(", ")}`,
  );
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    if (error instanceof AuditGateError) {
      console.error(`✗ dependency audit could not be completed: ${error.message}`);
      process.exit(1);
    }
    throw error;
  }
}

module.exports = { AuditGateError, SEVERITIES, collectAdvisories, evaluate, parseReport, readConfig };
