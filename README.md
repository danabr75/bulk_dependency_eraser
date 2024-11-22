# bulk_dependency_eraser
Delete records in bulk, and their dependencies, without instantiation or callbacks.


# Install (add to Gemfile)
`gem 'bulk_dependency_eraser'`

# WARNINGS!

### `ActiveRecord::InvalidForeignKey`
To accomplish efficient mass deletion, we suppress `ActiveRecord::InvalidForeignKey` errors.
It's upon you to ensure that your dependency trees in your models are set up properly, so as not to leave orphaned records.
You can disable this suppression, but you may run into deletion order issues.
- see `:enable_invalid_foreign_key_detection` option

### Rollbacks
- In v1.X, we used to run all deletions and nullifications in their own transaction blocks, but this appears to be causing some table locking issues. No longer using transaction blocks for this reason, and can no longer support rollbacks.
- You can still enable rollbacks if you want by passing in these two wrapper options.
```
opts: {
  db_delete_all_wrapper: ->(block) {
    ActiveRecord::Base.transaction do
      begin
        block.call # execute deletions
      rescue StandardError => e
        report_error("Issue attempting to delete '#{current_class_name}': #{e.class.name} - #{e.message}")
        raise ActiveRecord::Rollback
      end
    end
  },
  db_nullify_all_wrapper: ->(block) {
    ActiveRecord::Base.transaction do
      begin
        block.call # execute nullifications
      rescue StandardError => e
        report_error("Issue attempting to nullify '#{current_class_name}': #{e.class.name} - #{e.message}")
        raise ActiveRecord::Rollback
      end
    end
  }
}
BulkDependencyEraser::Manager.new(query: User.where(id: [...]), opts:).execute
```

# Example 1:
  ```
  # Delete all queried users and their dependencies.
  query = User.where(id: [...])
  manager = BulkDependencyEraser::Manager.new(query:)
  manager.execute #=> true/false, depending on if successful.
  ```

# Example 2:
  ```
  # To see the dependency tree actualized as ids mapped by class name
  query = User.where(id: [...])
  manager = BulkDependencyEraser::Manager.new(query:)
  manager.build #=> true/false, depending on if successful.

  # To see the Class/ID deletion data
  puts manager.deletion_list

  # To see the Class/Column/ID data
  # - It would nullify those columns for those class on those IDs.
  puts manager.nullification_list

  # If there are any errors encountered, the deletion/nullification will not take place.
  # You can see any errors here:
  puts manager.errors
  ```

# Data structure requirements
- Requires all query and dependency tables to have an 'id' column.
- This logic also requires that all the rails model association scopes not have parameters
  - We would need to instantiate the records to resolve those.
  - If you have to have association scopes with instance-level parameters, see the `:instantiate_if_assoc_scope_with_arity` option documentation.
- If any of these requirements are not met, an error will be reported and the deletion/nullification will not take effect.

# Options - Passing Them In
```
# pass options as :opts keyword arg
# - also valid for any other BulkDependencyEraser classes
opts = {<...>}
manager = BulkDependencyEraser::Manager.new(query:, opts:)
```

# Additional Options:

### Option: Ignore Tables
```
# Ignore tables
# - will still go through those tables to locate dependencies
opts: { ignore_tables: [User.table_name, <other_table_name>, ...] }
# - Those ignored table build results will be accessible via the following.
#   - Useful for handling those deletions with your own logic.
manager.ignore_table_deletion_list
manager.ignore_table_nullification_list

# You can delete/nullify these ignored tables manually:
deleter = BulkDependencyEraser::Deleter.new(
  class_names_and_ids: manager.ignore_table_deletion_list,
  opts:
)
deleter.execute
nullifier = BulkDependencyEraser::Nullifier.new(
  class_names_columns_and_ids: manager.ignore_table_nullification_list,
  opts:
)
nullifier.execute
```

### Option: Ignore Tables and Their Dependencies
```
# Ignore tables and their dependencies
# - will NOT go through those tables to locate dependencies
# - this option will not populate the 'ignore_table_nullification_list', 'ignore_table_deletion_list' lists
#   - We don't parse them, so they are not added
opts: { ignore_tables_and_dependencies: [<table_name>, ...] }
```

### Option: Ignore Classes and Their Dependencies
```
# Ignore class names and their dependencies
# - will NOT go through those tables to locate dependencies
# - this option will not populate the 'ignore_table_nullification_list', 'ignore_table_deletion_list' lists
#   - We don't parse them, so they are not added
opts: { ignore_klass_names_and_dependencies: [<class_name>, ...] }
```

### Option: Enable 'ActiveRecord::InvalidForeignKey' errors
```
# During mass, unordered deletions, sometimes 'ActiveRecord::InvalidForeignKey' errors would be raised.
# - We can't guarantee deletion order. 
# - Currently we delete in order of leaf to root klasses (Last In, First Out)
# - Ordering with self-referential associations or circular-model dependencies is problematic
#   - only in terms of ordering though. We can easily parse circular or self-referential dependencies
#
# Therefore we use 'ActiveRecord::Base.connection.disable_referential_integrity' for deletions
# However, you can disable this by passing this value in options:
opts: { enable_invalid_foreign_key_detection: true }
```

### Option: Destroy 'restrict_with_error' or 'restrict_with_exeception' dependencies
```
# To delete associations with dependency values 'restrict_with_error' or 'restrict_with_exception',
# use the following option:
# - otherwise an error will be reported and deletions/nullifications will not occur
opts: { force_destroy_restricted: true }
```

### Option: Database Wrappers
```
You can wrap your database calls using the following options.

# You can pass your own procs if you wish to use different database call wrappers.
# By default, the database reading will be done through the :reading role
DATABASE_READ_WRAPPER = ->(block) do
  ActiveRecord::Base.connected_to(role: :reading) do
    block.call
  end
end

opts: { db_read_wrapper: DATABASE_READ_WRAPPER }

# By default, the database deletion and nullification will be done the :writing role
# You can override each wrapper individually.
DATABASE_WRITE_WRAPPER = ->(block) do
  ActiveRecord::Base.connected_to(role: :writing) do
    block.call
  end
end

# Deletion wrapper
opts: { db_delete_wrapper: DATABASE_WRITE_WRAPPER }

# Column Nullification wrapper
opts: { db_nullify_wrapper: DATABASE_WRITE_WRAPPER }
```

### Option: Batching (reading, deleting, nullifying)
```
# You can pass custom batch limits.

# Reading default: 10,000
# Deleting default: 300
# Nullification default: 300
opts: { batch_size: <Integer> } # will be applied to all actions (reading/deleting/nullifying)

opts: { read_batch_size: <Integer> }    # will be applied to reading (and will override :batch_size for reading)

opts: { delete_batch_size: <Integer> }  # will be applied to reading (and will override :batch_size for deleting)

opts: { nullify_batch_size: <Integer> } # will be applied to reading (and will override :batch_size for deleting)
```

### TODO: Option: Instantiation
- Feature currently is in development
```
# You have an association with instance-level parameters in it's association scope.
# - You can utilize the :instantiate_if_assoc_scope_with_arity option to have this gem 
#   instantiate those parent records to resolve and pluck the IDs of those associations
# - It will not have the same dependency tree parsing speed that you've come to know and love
opts: { instantiate_if_assoc_scope_with_arity: true }

# You can also set the batching, default 500, for those record instantiations
opts: {
  instantiate_if_assoc_scope_with_arity: true,
  batching_size_limit: 500
}
```
