class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users, force: true do |t|
      t.integer :uid
    end
  end
end
