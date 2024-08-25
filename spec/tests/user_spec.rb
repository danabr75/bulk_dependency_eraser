# require 'rails_helper'

# RSpec.describe User do
#   fixtures :users

  
#   it "should cache the serializer method and be clearable (instance method)" do
#     user = User.find_by_email('test@test.test')

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )

#     user.update(first_name: 'Neb')

#     expect(User.find_by_email('test@test.test').first_name).to eq('Neb')

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )

#     user.clear_serializer_cache

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Neb", "last_name"=>"Dana"}
#     )

#   end

#   it "should cache the serializer method and be clearable (class method)" do
#     user = User.find_by_email('test@test.test')

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )

#     user.update(first_name: 'Neb')

#     expect(User.find_by_email('test@test.test').first_name).to eq('Neb')

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )

#     User.clear_serializer_cache(user.id)

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Neb", "last_name"=>"Dana"}
#     )
#   end


#   it "should cache the serializer method and be clearable by the class method on multiple IDs" do
#     user_1 = User.find_by_email('test@test.test')
#     user_2 = User.find_by_email('test2@test.test')

#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Victor", "last_name"=>"Frankenstein"}
#     )

#     user_1.update(first_name: 'Neb')
#     user_2.update(first_name: 'Mary')

#     expect(User.find_by_email('test@test.test').first_name).to eq('Neb')
#     expect(User.find_by_email('test2@test.test').first_name).to eq('Mary')

#     # confirm cache hasn't changed
#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Victor", "last_name"=>"Frankenstein"}
#     )

#     User.clear_serializer_cache([user_1.id, user_2.id])

#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Neb", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Mary", "last_name"=>"Frankenstein"}
#     )
#   end

#   it "should cache the serializer method and be clearable by the class method on multiple IDs (with compression)" do
#     allow(Serializer.configuration).to receive(:compress).and_return(true)
#     expect(Serializer.configuration.compress).to eq(true)
    
#     user_1 = User.find_by_email('test@test.test')
#     user_2 = User.find_by_email('test2@test.test')

#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Victor", "last_name"=>"Frankenstein"}
#     )

#     user_1.update(first_name: 'Neb')
#     user_2.update(first_name: 'Mary')

#     expect(User.find_by_email('test@test.test').first_name).to eq('Neb')
#     expect(User.find_by_email('test2@test.test').first_name).to eq('Mary')

#     # confirm cache hasn't changed
#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Victor", "last_name"=>"Frankenstein"}
#     )

#     User.clear_serializer_cache([user_1.id, user_2.id])

#     expect(user_1.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Neb", "last_name"=>"Dana"}
#     )
#     expect(user_2.serializer).to eq(
#       {"id"=>2, "email"=>"test2@test.test", "first_name"=>"Mary", "last_name"=>"Frankenstein"}
#     )
#   end


#   it "should have only 2 query key in it's serializer key cache constant" do
#     expect(User::SERIALIZER_QUERY_KEYS_CACHE).to eq([:with_vehicle_parts_serializer_query, :serializer_query] )
#   end

#   it "should attach the inherited serializer method" do
#     user = User.find_by_email('test@test.test')

#     expect(user.serializer).to eq(
#       {"id"=>1, "email"=>"test@test.test", "first_name"=>"Ben", "last_name"=>"Dana"}
#     )
#   end
# end