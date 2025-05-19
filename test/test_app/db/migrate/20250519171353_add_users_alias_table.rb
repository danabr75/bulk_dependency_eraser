# Can't be created in schema.rb file (triggers not supported)
class AddUsersAliasTable < ActiveRecord::Migration[6.1]
  def up
    execute <<~SQL
      CREATE VIEW users_alias AS
      SELECT * FROM users;
    SQL

    # SQL compatible
    # FWD deletions to users table
    # execute <<~SQL
    #   CREATE FUNCTION handle_delete_from_users_alias() RETURNS trigger AS $$
    #   BEGIN
    #     DELETE FROM users WHERE id = OLD.id;
    #     RETURN OLD;
    #   END;
    #   $$ LANGUAGE plpgsql;
    # SQL
    # execute <<~SQL
    #   CREATE TRIGGER users_alias_delete_trigger
    #   INSTEAD OF DELETE ON users_alias
    #   FOR EACH ROW
    #   EXECUTE FUNCTION handle_delete_from_users_alias();
    # SQL

    # SQLite3 compatible
    execute <<~SQL
      CREATE TRIGGER users_alias_delete_trigger
      INSTEAD OF DELETE ON users_alias
      BEGIN
        DELETE FROM users WHERE id = OLD.id;
      END;
    SQL
  end

  def down
    # SQL compatible
    # execute <<~SQL
    #   DROP TRIGGER IF EXISTS users_alias_delete_trigger ON users_alias;
    # SQL
    # execute <<~SQL
    #   DROP FUNCTION IF EXISTS handle_delete_from_users_alias();
    # SQL

    # SQLite3 compatible
    execute <<~SQL
      DROP TRIGGER IF EXISTS event_alias_delete_trigger;
    SQL

    execute <<~SQL
      DROP VIEW IF EXISTS users_alias;
    SQL
  end
end