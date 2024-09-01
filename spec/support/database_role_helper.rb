def expect_connected_to_role(role)
  expect(ActiveRecord::Base.connection.current_role).to eq(role)
end