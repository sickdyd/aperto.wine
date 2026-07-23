class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  # db/cache_schema.rb is loaded by this shipped migration: never edit it in
  # place — gem upgrades that change the schema need a new migration.
  def up
    load Rails.root.join("db/cache_schema.rb")
  end

  def down
    drop_table :solid_cache_entries
  end
end
