require "test_helper"

# rails_icons reads its SVGs straight off the filesystem, so the ~9k synced
# files must NOT also be digested into public/assets by Propshaft.
class IconAssetPipelineTest < ActiveSupport::TestCase
  include RailsIcons::Helpers::IconHelper

  test "the icon directory is excluded from the asset pipeline" do
    paths = Rails.application.config.assets.paths.map(&:to_s)

    refute_includes paths, Rails.root.join("app/assets/svg").to_s,
      "precompiling the icon set copies ~35 MB of SVGs into public/assets for nothing"
  end

  test "icons still render once the directory is excluded" do
    svg = icon("wine")

    assert_match(/\A<svg/, svg)
    # Nokogiri's HTML parser downcases attribute names, so viewBox arrives as viewbox.
    assert_match(/viewbox="0 0 256 256"/, svg)
  end
end
