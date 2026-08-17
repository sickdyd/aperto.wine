# Optimistic locking for the owner's wine form.
#
# available_glasses is now a live reservation counter that diners move
# underneath the owner, but the form still edits it as an absolute number
# seeded when the page was rendered. An owner who opens the form at 10, leaves
# it sitting while diners reserve 4, then saves an unrelated typo fix would
# write 10 back and resurrect the four reserved glasses. The window is however
# long the form stays open, not a millisecond race.
#
# lock_version turns that silent overwrite into a StaleObjectError the
# controller can show the owner (see Owner::WinesController#update).
class AddLockVersionToWines < ActiveRecord::Migration[8.1]
  def change
    add_column :wines, :lock_version, :integer, null: false, default: 0
  end
end
