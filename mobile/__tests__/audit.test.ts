import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const {
  AuditGateError,
  collectAdvisories,
  evaluate,
  parseReport,
  readConfig,
} = require("../scripts/audit.js");

/**
 * The gate's whole reason for existing is that it refuses to reach a verdict
 * from a report it does not recognise — audit-ci, which it replaced, answered
 * "passed" to an unreadable audit. So most of what follows is not "does it
 * spot a vulnerability" but "does it decline to say the tree is clean".
 */

const advisory = (id: string, severity: string, name: string) => ({
  source: 1,
  name,
  title: `${name} is vulnerable`,
  url: `https://github.com/advisories/${id}`,
  severity,
});

const report = (vulnerabilities: Record<string, unknown> = {}) => ({
  auditReportVersion: 2,
  vulnerabilities,
  metadata: {
    vulnerabilities: { info: 0, low: 0, moderate: 0, high: 0, critical: 0, total: 0 },
    dependencies: { total: 1 },
  },
});

const withConfig = (body: string, run: (file: string) => void) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "audit-gate-"));
  const file = path.join(directory, "audit-allowlist.jsonc");
  fs.writeFileSync(file, body);
  try {
    run(file);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
};

describe("parseReport", () => {
  it("accepts a well-formed report whether or not npm found anything", () => {
    expect(parseReport(JSON.stringify(report()), 0)).toMatchObject({ auditReportVersion: 2 });
    expect(parseReport(JSON.stringify(report()), 1)).toMatchObject({ auditReportVersion: 2 });
  });

  // npm exits 0 clean and 1 when it found something. Anything else is npm
  // failing rather than reporting, and a failure to run is not evidence of a
  // clean tree.
  it.each([
    ["a crash", 127],
    ["an unexpected code", 2],
    ["a signal", null],
  ])("refuses to conclude anything from %s", (_label, status) => {
    expect(() => parseReport(JSON.stringify(report()), status)).toThrow(AuditGateError);
  });

  it.each([
    ["no output at all", ""],
    ["only whitespace", "   \n  "],
    ["truncated JSON", '{"vulnerabilities": {'],
    ["a registry error page", "<html>502 Bad Gateway</html>"],
    ["a bare null", "null"],
    ["an array", "[]"],
  ])("refuses %s", (_label, stdout) => {
    expect(() => parseReport(stdout, 0)).toThrow(AuditGateError);
  });

  // The failure mode this gate exists for: npm reshapes its output, and a
  // tolerant parser reads the new shape as "nothing found".
  it("refuses a report format it does not understand rather than reading it as clean", () => {
    const future = JSON.stringify({ auditReportVersion: 3, findings: [] });
    expect(() => parseReport(future, 0)).toThrow(/only understands version 2/);
    expect(() => parseReport(future, 0)).toThrow(/do not assume the tree is clean/);
  });

  it("refuses a report with no version stamp", () => {
    expect(() => parseReport(JSON.stringify({ vulnerabilities: {}, metadata: {} }), 0)).toThrow(
      AuditGateError,
    );
  });

  it.each([
    ["no vulnerabilities object", { ...report(), vulnerabilities: undefined }],
    ["vulnerabilities as an array", { ...report(), vulnerabilities: [] }],
    ["no metadata counts", { ...report(), metadata: {} }],
    [
      "a non-numeric count",
      { ...report(), metadata: { vulnerabilities: { info: 0, low: 0, moderate: "?", high: 0, critical: 0 } } },
    ],
  ])("refuses a report with %s", (_label, payload) => {
    expect(() => parseReport(JSON.stringify(payload), 0)).toThrow(AuditGateError);
  });
});

describe("collectAdvisories", () => {
  it("collects each advisory once, however many packages carry it", () => {
    const collected = collectAdvisories(
      report({
        // npm repeats one advisory under every package it propagates through.
        "image-size": { via: [advisory("GHSA-w3rx-r6r6-pgpr", "high", "image-size")] },
        metro: { via: ["image-size", advisory("GHSA-w3rx-r6r6-pgpr", "high", "image-size")] },
        uuid: { via: [advisory("GHSA-w5hq-g745-h8pq", "moderate", "uuid")] },
      }),
    );

    expect([...collected.keys()].sort()).toEqual(["GHSA-w3rx-r6r6-pgpr", "GHSA-w5hq-g745-h8pq"]);
    expect(collected.get("GHSA-w3rx-r6r6-pgpr").severity).toBe("high");
  });

  it("ignores packages that are only vulnerable through something else", () => {
    expect(collectAdvisories(report({ metro: { via: ["image-size"] } })).size).toBe(0);
  });

  // An advisory with no id cannot be triaged or allowlisted, so it must not be
  // silently dropped from the count either.
  it("refuses an advisory it cannot identify", () => {
    const unidentifiable = report({ mystery: { via: [{ severity: "high", url: "https://example.com/x" }] } });
    expect(() => collectAdvisories(unidentifiable)).toThrow(/cannot identify/);
  });

  it("refuses an advisory with an unrecognised severity", () => {
    const odd = report({ x: { via: [advisory("GHSA-w3rx-r6r6-pgpr", "catastrophic", "x")] } });
    expect(() => collectAdvisories(odd)).toThrow(/unrecognised severity/);
  });
});

describe("evaluate", () => {
  const config = { failOnSeverity: "moderate", allowlist: ["GHSA-w3rx-r6r6-pgpr"] };
  const found = (entries: [string, string][]) =>
    new Map(entries.map(([id, severity]) => [id, { severity, packages: new Set(["pkg"]) }]));

  it("passes an allowlisted advisory", () => {
    expect(evaluate(found([["GHSA-w3rx-r6r6-pgpr", "high"]]), config)).toEqual({
      unexpected: [],
      stale: [],
    });
  });

  it("fails a new advisory in a package that is already allowlisted for another", () => {
    const { unexpected } = evaluate(
      found([
        ["GHSA-w3rx-r6r6-pgpr", "high"],
        ["GHSA-aaaa-bbbb-cccc", "critical"],
      ]),
      config,
    );
    expect(unexpected.map((u: { id: string }) => u.id)).toEqual(["GHSA-aaaa-bbbb-cccc"]);
  });

  it("ignores advisories below the threshold", () => {
    expect(evaluate(found([["GHSA-aaaa-bbbb-cccc", "low"]]), config).unexpected).toEqual([]);
  });

  // Both halves of the same rule: it forces a fixed advisory out of the list,
  // and it is the net that catches a report which came back without the
  // advisories we know are in this tree.
  it("fails an allowlist entry that the report no longer mentions", () => {
    expect(evaluate(found([]), config).stale).toEqual(["GHSA-w3rx-r6r6-pgpr"]);
  });
});

describe("readConfig", () => {
  it("reads the real allowlist, comments and all", () => {
    const config = readConfig(path.join(__dirname, "..", "audit-allowlist.jsonc"));
    expect(config.failOnSeverity).toBe("moderate");
    expect(config.allowlist.length).toBeGreaterThan(0);
  });

  it("refuses a package name where an advisory id belongs", () => {
    withConfig('{"failOnSeverity":"moderate","allowlist":["image-size"]}', (file) => {
      expect(() => readConfig(file)).toThrow(/not a GitHub advisory id/);
    });
  });

  it("refuses a severity threshold it does not recognise", () => {
    withConfig('{"failOnSeverity":"whenever","allowlist":[]}', (file) => {
      expect(() => readConfig(file)).toThrow(/failOnSeverity must be one of/);
    });
  });

  it("strips whole-line comments without touching the JSON", () => {
    withConfig(
      '// a note\n{\n  // another\n  "failOnSeverity": "high",\n  "allowlist": []\n}\n',
      (file) => expect(readConfig(file).failOnSeverity).toBe("high"),
    );
  });
});
