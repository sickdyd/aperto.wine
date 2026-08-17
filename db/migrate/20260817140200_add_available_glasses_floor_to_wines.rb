# Backs Wine's `numericality: { greater_than_or_equal_to: 0 }` with a DB-level
# guard, following the precedent set by AddEnrichmentFieldsToWines.
#
# It matters more here than it does for the enrichment columns: the reservation
# path decrements through `decrement!`, which routes into `update_counters` and
# skips validations entirely, so the Ruby validation protects only the owner's
# form. Without this constraint a stock bug could drive the column negative and
# leave no trace of when it happened.
#
# Additive and already satisfied by every existing row, so it ships in the same
# deploy as the code — unlike a destructive change, which has to wait for a
# later one (see CLAUDE.md on Render's preDeployCommand).
class AddAvailableGlassesFloorToWines < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :wines, "available_glasses >= 0", name: "wines_available_glasses_non_negative"
  end
end
