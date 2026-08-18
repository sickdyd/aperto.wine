require "test_helper"

# Guards the Expo client's bundle-size gate.
#
# Like the audit gate next door, this one lives entirely outside the Ruby app —
# a Node script and a CI step — so nothing else in the suite touches it. Its
# failure mode is the quiet kind: unwire the step and the app goes back to
# shipping whatever Metro happens to pull in, with every check still green. The
# regression it exists to stop already happened once, at 5.5MB of typefaces no
# screen could render.
class MobileBundleGateTest < ActiveSupport::TestCase
  PACKAGE = Rails.root.join("mobile/package.json")
  SCRIPT = Rails.root.join("mobile/scripts/check-bundle.mjs")
  WORKFLOW = Rails.root.join(".github/workflows/ci.yml")

  setup do
    @package = JSON.parse(PACKAGE.read)
    @workflow = YAML.safe_load_file(WORKFLOW, aliases: true)
  end

  test "the check is runnable" do
    assert_equal "node scripts/check-bundle.mjs", @package.dig("scripts", "check:bundle")
    assert SCRIPT.exist?, "the check:bundle script points at a file that does not exist"
  end

  test "CI runs the gate for the Expo client" do
    steps = @workflow.dig("jobs", "mobile", "steps")
    assert steps, "expected a mobile job in the CI workflow"
    assert steps.any? { |step| step["run"].to_s.strip == "npm run check:bundle" },
      "nothing in the mobile CI job checks the bundle, so a font family could " \
      "come back in unnoticed"
  end

  test "the gate asserts against what the layout imports rather than a hardcoded list" do
    source = SCRIPT.read
    assert_match "_layout.tsx", source,
      "deriving the expected typefaces from the layout is what keeps the gate " \
      "correct when a face is legitimately added or dropped"
    assert_match(/process\.exit\(1\)/, source,
      "a check that reports a problem without a non-zero exit does not gate anything")
  end
end
