# Wine reference catalogue (X-Wines, CC0-1.0) — powers the owner type-ahead in
# every environment. The importer upserts on external_id, so re-seeding is safe.
wine_reference_summary = WineReferences::Importer.call
puts "Wine references: #{wine_reference_summary} (total #{WineReference.count})"
# Same contract as the wine_references:import rake task: a truncated parse is a
# broken catalogue, so fail the seed instead of leaving a partial table behind.
raise "Wine reference import truncated: #{wine_reference_summary.error}" if wine_reference_summary.truncated?

# Demo accounts, a sample restaurant and its wines. Development loads them
# automatically. Deployed environments load them on demand, so staging can use
# the quick-login buttons (see SHOW_DEV_LOGIN in render.yaml):
#
#   bin/rails runner 'load Rails.root.join("db/seeds/demo.rb")'
load Rails.root.join("db/seeds/demo.rb") if Rails.env.development?
