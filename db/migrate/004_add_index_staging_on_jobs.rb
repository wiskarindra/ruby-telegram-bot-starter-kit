class AddIndexStagingOnJobs < ActiveRecord::Migration
  def change
    add_index :jobs, [:staging, :created_at]
  end
end
