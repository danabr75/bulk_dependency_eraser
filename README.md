# bulk_dependency_eraser
Delete records in bulk, and their dependencies, without instantiation or callbacks.


# Install
gem 'bulk_dependency_eraser'

# Ex usage:
  ```
  # Delete all queried users and their dependecies.
  query = User.where(id: [...])
  bdem = BulkDependencyEraser::Manager.new(query:)
  bdem.execute
  ```
  ```
  # To see the dependency tree
  query = User.where(id: [...])
  bdem = BulkDependencyEraser::Manager.new(query:)
  bdem.build

  # To see the Class/ID deletion data
  puts bdem.deletion_list

  # To see the Class/Column/ID data, where it would nullify those columns for those class on those IDs.
  puts bdem.nullification_list
  ```

# Data structure requirements
- Requires all query and dependency tables to have an 'id' column.
- Requires that all query and dependency associations not have scopes with parameters (we would need to instantiate to resolve)
  - There is a option that we're working on that would attempt to instantiate records so that we could resolve those scopes.
- If any of these requirements are not met, an error will be reported and the deletion/nullification will not take effect.