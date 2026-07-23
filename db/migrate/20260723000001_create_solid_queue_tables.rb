class CreateSolidQueueTables < ActiveRecord::Migration[8.1]
  # db/queue_schema.rb is loaded by this shipped migration: never edit it in
  # place — gem upgrades that change the schema need a new migration.
  def up
    load Rails.root.join("db/queue_schema.rb")
  end

  def down
    # Children with a foreign key to solid_queue_jobs must drop first.
    drop_table :solid_queue_semaphores
    drop_table :solid_queue_scheduled_executions
    drop_table :solid_queue_recurring_tasks
    drop_table :solid_queue_recurring_executions
    drop_table :solid_queue_ready_executions
    drop_table :solid_queue_processes
    drop_table :solid_queue_pauses
    drop_table :solid_queue_failed_executions
    drop_table :solid_queue_claimed_executions
    drop_table :solid_queue_blocked_executions
    drop_table :solid_queue_jobs
  end
end
