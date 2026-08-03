require "test_helper"

# Guards the Render deploy contract. These files are only exercised by an actual
# deploy, so a mistake here surfaces as a broken staging environment rather than
# a failing test — hence the coverage.
class RenderBlueprintTest < ActiveSupport::TestCase
  BLUEPRINT = Rails.root.join("render.yaml")
  BUILD_SCRIPT = Rails.root.join("bin/render-build.sh")

  # Matches ENV["FOO"] and ENV.fetch("FOO", ...) — the two forms used in app/.
  ENV_REFERENCE = /ENV(?:\[|\.fetch\()"([A-Z][A-Z0-9_]*)"/

  # Read by the runtime but supplied by the platform, not the blueprint.
  PLATFORM_PROVIDED = %w[PORT PIDFILE RAILS_ENV].freeze

  setup do
    @blueprint = YAML.safe_load_file(BLUEPRINT)
    @staging = @blueprint.fetch("services").find { |s| s["name"] == "aperto-wine-staging" }
    # Comments explain what the script deliberately does NOT do, so assertions
    # about the script's behaviour have to look at the commands alone.
    @build_script = BUILD_SCRIPT.read.lines.grep_v(/\A\s*(#|\z)/).join
  end

  test "staging web service is defined" do
    assert @staging, "expected a service named aperto-wine-staging in render.yaml"
    assert_equal "web", @staging["type"]
  end

  test "staging is pinned to a region close to Italian users" do
    assert_equal "frankfurt", @staging["region"],
      "region is fixed at creation time; leaving it unset silently defaults to Oregon"
  end

  test "migrations run as a pre-deploy command, not during the build" do
    assert_includes @staging["preDeployCommand"].to_s, "db:migrate",
      "Render runs preDeployCommand after the build and before traffic switches, " \
      "so a failed migration halts the deploy with the old version still serving"
  end

  test "the build script does not also run migrations" do
    refute_match(/db:migrate/, @build_script,
      "migrating in both places runs migrations twice per deploy")
  end

  test "the build script syncs the icon set" do
    assert_match(/rails_icons:sync/, @build_script,
      "app/assets/svg/icons is gitignored (see docs/ASSETS.md); without a sync step " \
      "every icon(...) call raises Icons::IconNotFound at request time")
  end

  test "the build script precompiles assets after syncing icons" do
    sync_at = @build_script.index("rails_icons:sync")
    precompile_at = @build_script.index("assets:precompile")

    assert precompile_at, "expected the build script to precompile assets"
    assert sync_at < precompile_at, "icons must be synced before assets are precompiled"
  end

  test "RAILS_ENV is set explicitly" do
    assert_equal "production", env_vars(@staging)["RAILS_ENV"],
      "the build and pre-deploy commands do not pass -e, so they inherit RAILS_ENV"
  end

  test "every environment variable read by app code is declared" do
    declared = env_vars(@staging).keys

    (referenced_env_vars - PLATFORM_PROVIDED).each do |name|
      assert_includes declared, name,
        "#{name} is read by app/ but is not declared for the staging service"
    end
  end

  test "secrets are not committed to the blueprint" do
    %w[HTTP_AUTH_USER HTTP_AUTH_PASSWORD WINE_SEARCHER_API_KEY].each do |name|
      entry = @staging["envVars"].find { |var| var["key"] == name }

      assert entry, "#{name} should be declared"
      assert_equal false, entry["sync"], "#{name} must be set in the dashboard, not in the repo"
      assert_nil entry["value"], "#{name} must not carry a literal value"
    end
  end

  private

  # Only the keys with an inline literal; sync:false and fromDatabase entries
  # resolve outside the blueprint.
  def env_vars(service)
    service.fetch("envVars").to_h { |var| [ var["key"], var["value"] ] }
  end

  def referenced_env_vars
    Rails.root.glob("app/**/*.rb").flat_map { |file| file.read.scan(ENV_REFERENCE) }.flatten.uniq.sort
  end
end
