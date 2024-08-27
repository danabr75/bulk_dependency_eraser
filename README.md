# bulk_dependency_eraser
Delete records in bulk, and their dependencies, without instantiation or callbacks.


# Install
gem 'bulk_dependency_eraser'

# Ex usage:
  ```
  # Delete all queried users and their dependencies.
  query = User.where(id: [...])
  bdem = BulkDependencyEraser::Manager.new(query:)
  bdem.execute #=> true/false, depending on if successful.
  ```
  ```
  # To see the dependency tree
  query = User.where(id: [...])
  bdem = BulkDependencyEraser::Manager.new(query:)
  bdem.build #=> true/false, depending on if successful.

  # To see the Class/ID deletion data
  puts bdem.deletion_list

  # To see the Class/Column/ID data, where it would nullify those columns for those class on those IDs.
  puts bdem.nullification_list

  # If there are any errors encountered, the deletion/nullification will not take place.
  # You can see any errors here:
  puts bdem.errors
  ```

# Data structure requirements
- Requires all query and dependency tables to have an 'id' column.
- Requires that all query and dependency associations not have scopes with parameters (we would need to instantiate to resolve)
  - There is a option that we're working on that would attempt to instantiate records so that we could resolve those scopes.
- If any of these requirements are not met, an error will be reported and the deletion/nullification will not take effect.

# Options
```
# pass options as :opts keyword arg
bdem = BulkDependencyEraser::Manager.new(query:, opts:)

# Ignore tables (will still go through those tables to locate dependencies)
# - those ignored table build results will be accessible via the following. Useful for handling those deletions with your own logic.
#   - bdem.ignore_table_nullification_list
#   - bdem.ignore_table_deletion_list
opts: { ignore_tables: [<table_name>, ...] }

# Ignore tables and their dependencies deletion/nullification lists (will still go through those tables to locate dependencies)
# - this option will not populate the 'ignore_table_nullification_list', 'ignore_table_deletion_list' lists (because they are not parsed)
opts: { ignore_tables_and_dependencies: [<table_name>, ...] }

# Since we're doing mass deletions, sometimes 'ActiveRecord::InvalidForeignKey' errors are raised.
# - We can't guarantee deletion order, especially if you have self-referential associations or circular-model dependencies.
# We use 'ActiveRecord::Base.connection.disable_referential_integrity' blocks to avoid that, but
# you can disable this by passing this value in options.
# If this error, or any other error, occurs during deletions, all deletions will be rolled back.
opts: { enable_invalid_foreign_key_detection: true }

# To delete associations with dependency values 'restrict_with_error' or 'restrict_with_exception',
# use the following option:
# - otherwise an error will be reported and deletions/nullifications will not occur
opts: { force_destroy_restricted: true }
```




