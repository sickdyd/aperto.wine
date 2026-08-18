require "test_helper"

# Guards the Expo client's dependency-vulnerability gate.
#
# The gate lives entirely outside the Ruby app — an npm script, a CI step, a Git
# hook — so nothing here is exercised by the rest of the suite. Its failure mode
# is also silent in the worst way: a gate that has been unwired, loosened, or
# quietly widened until it allows everything still reports green. These
# assertions are what makes that visible.
class MobileAuditGateTest < ActiveSupport::TestCase
  CONFIG = Rails.root.join("mobile/audit-ci.jsonc")
  PACKAGE = Rails.root.join("mobile/package.json")
  WORKFLOW = Rails.root.join(".github/workflows/ci.yml")
  LEFTHOOK = Rails.root.join("lefthook.yml")

  # audit-ci treats a bare GitHub advisory id as "this specific finding", but a
  # bare module name as "anything ever reported against this package". Only the
  # former is a triage decision.
  ADVISORY_ID = /\AGHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}\z/

  setup do
    @config_source = CONFIG.read
    # jsonc, so strip whole-line comments before parsing. Only lines that *open*
    # with the marker are dropped, which leaves any `//` inside a JSON string
    # alone.
    @config = JSON.parse(@config_source.lines.grep_v(/\A\s*\/\//).join)
    @package = JSON.parse(PACKAGE.read)
    @workflow = YAML.safe_load_file(WORKFLOW, aliases: true)
    @lefthook = YAML.safe_load_file(LEFTHOOK, aliases: true)
  end

  test "the gate is declared as an npm script backed by an installed tool" do
    assert_equal "audit-ci --config audit-ci.jsonc --report-type summary",
      @package.dig("scripts", "audit")
    assert @package.dig("devDependencies", "audit-ci"),
      "the audit script is unrunnable in CI unless audit-ci is in devDependencies"
  end

  test "CI runs the gate for the Expo client" do
    steps = @workflow.dig("jobs", "mobile", "steps")
    assert steps, "expected a mobile job in the CI workflow"
    assert steps.any? { |step| step["run"].to_s.strip == "npm run audit" },
      "nothing in the mobile CI job runs the audit gate, so a new advisory would land unnoticed"
  end

  test "committing a change to the Expo lockfile runs the gate locally" do
    command = @lefthook.dig("pre-commit", "commands", "mobile-npm-audit")
    assert command, "expected a mobile-npm-audit pre-commit command"
    assert_equal "mobile/", command["root"],
      "the gate has to run from mobile/, where the Expo lockfile and audit-ci.jsonc live"
    assert_equal "npm run audit", command["run"]
    assert_equal "mobile/{package.json,package-lock.json}", command["glob"],
      "a root-relative glob would either miss the Expo lockfile or fire on the Rails one"
  end

  test "the Rails audit hook stays scoped to the repo root" do
    command = @lefthook.dig("pre-commit", "commands", "npm-audit")
    assert_equal "{package.json,package-lock.json}", command["glob"],
      "widening this glob runs the repo-root audit against the Expo client's tree, " \
      "which scans the wrong dependencies and still leaves the right ones ungated"
  end

  test "the gate fails at moderate, matching the Rails side" do
    assert @config["moderate"],
      "audit-ci names its threshold as the lowest severity that fails; without this key " \
      "the gate has been relaxed to high or above"
  end

  test "development dependencies are audited too" do
    refute @config["skip-dev"],
      "Expo's whole build toolchain is a devDependency — skipping dev audits nothing that matters"
  end

  test "every allowlist entry names one advisory rather than a whole package" do
    @config.fetch("allowlist").each do |entry|
      assert_match ADVISORY_ID, entry,
        "#{entry.inspect} is not an advisory id. A module name here suppresses every " \
        "present and future advisory against that package, which is not a triage decision."
    end
  end

  # The point of an allowlist is that it shrinks. An entry with no stated exit
  # condition never gets revisited, and the gate erodes one accepted advisory at
  # a time.
  test "every allowlist entry states what would let it be removed" do
    justifications = allowlist_justifications

    @config.fetch("allowlist").each do |entry|
      comment = justifications.fetch(entry, "")
      assert_includes comment, "Remove when:",
        "#{entry} is allowlisted with no removal condition. Say what upstream change " \
        "retires it, so the next reader can delete the entry instead of guessing."
    end
  end

  private
    # Maps each allowlisted advisory id to the comment block that introduces it.
    # Consecutive ids share the block above them, which is how a single advisory
    # affecting one package through one path is documented once.
    def allowlist_justifications
      block = []
      @config_source.lines.each_with_object({}) do |line, justifications|
        case line
        when /\A\s*\/\/(.*)/ then block += [ $1 ]
        # Deliberately does not clear the block: consecutive ids are one advisory
        # group and share the comment written above them.
        when /"(GHSA-[0-9a-z-]+)"/ then justifications[$1] = block.join("\n")
        else block = []
        end
      end
    end
end
