require "test_helper"

# The Dockerfile is the Kamal deploy path, and Render auto-detects it for any
# service created through the dashboard rather than the Blueprint. Nothing else
# in the suite executes it, so the two things a clean clone is missing at build
# time are asserted here. The image is actually built in CI.
class DockerfileTest < ActiveSupport::TestCase
  DOCKERFILE = Rails.root.join("Dockerfile")
  TAILWIND_ENTRYPOINT = Rails.root.join("app/assets/tailwind/application.css")

  setup do
    @dockerfile = DOCKERFILE.read.lines.grep_v(/\A\s*(#|\z)/).join
  end

  test "npm plugins loaded by the Tailwind build are installed into the image" do
    plugins = TAILWIND_ENTRYPOINT.read.scan(/@plugin\s+"([^"\/]+)/).flatten.uniq

    assert_includes plugins, "daisyui", "expected the Tailwind entrypoint to load daisyui"
    assert_match(/npm ci/, @dockerfile,
      "the standalone Tailwind binary resolves #{plugins.join(", ")} from node_modules, " \
      "which .dockerignore excludes from the build context")
  end

  test "node_modules reaches the stage that precompiles assets" do
    # Anchored on the COPY itself, not the bare word: "node_modules" also names
    # the stage it comes from, so a looser match stays green after the COPY is
    # deleted — which is the exact regression this guards.
    copy_at = @dockerfile.index(/^COPY --from=node_modules \S+ /)
    precompile_at = @dockerfile.index("assets:precompile")

    assert copy_at, "expected node_modules to be copied into the build stage"
    assert precompile_at, "expected the Dockerfile to precompile assets"
    assert copy_at < precompile_at, "node_modules must be in place before assets:precompile"
  end

  test "the icon set is synced into the image" do
    assert_match(/rails_icons:sync/, @dockerfile,
      "app/assets/svg/icons is gitignored (docs/ASSETS.md), so it is absent from a " \
      "clean clone; without a sync step every icon(...) call raises Icons::IconNotFound")
  end

  test "the icon sync runs before assets are precompiled" do
    sync_at = @dockerfile.index("rails_icons:sync")
    precompile_at = @dockerfile.index("assets:precompile")

    assert sync_at, "expected the Dockerfile to sync icons"
    assert sync_at < precompile_at, "icons must be synced before assets are precompiled"
  end
end
