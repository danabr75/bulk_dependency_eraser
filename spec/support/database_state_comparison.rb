def get_db_snapshot
  klasses_and_ids = {}
  ALL_DATABASE_TABLES.call.each do |table_name|
    klass = table_name.classify.constantize
    columns = ActiveRecord::Base.connection.columns(table_name).map(&:name)
    
    if klass.primary_key == 'id'
      ids = ActiveRecord::Base.connection.select_values("SELECT id FROM #{table_name}")
      klasses_and_ids[klass.name] = ids.sort
    else
      # Handle tables without an id column
      id_columns = columns.select { |col| col.ends_with?('_id') }
      unless id_columns.empty?
        result = ActiveRecord::Base.connection.select_all("SELECT #{id_columns.join(', ')} FROM #{table_name}")
        # join the foreign keys to form a new primary_id
        klasses_and_ids[klass.name] = result.map(&:to_h).map(&:values).collect {|v| v.join('_')}.sort
      end
    end
  end

  return klasses_and_ids
end

def compare_db_snapshot original_klasses_and_ids
  current_klasses_and_ids = get_db_snapshot
  deleted = {}
  added   = {}


  original_klasses_and_ids.each do |klass_name, ids|
    deleted[klass_name] = ids - current_klasses_and_ids[klass_name]
    deleted.delete(klass_name) if deleted[klass_name].none?
  end

  current_klasses_and_ids.each do |klass_name, ids|
    added[klass_name] = ids - original_klasses_and_ids[klass_name]
    added.delete(klass_name) if added[klass_name].none?
  end


  return {deleted:, added:}
end