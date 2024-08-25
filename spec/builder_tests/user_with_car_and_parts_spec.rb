# require 'rails_helper'

# RSpec.describe User do
#   fixtures :users, :vehicles, :parts

#   it "should load in fixtures" do
#     expect(User.count).to eq(2)
#     expect(Vehicle.count).to eq(4)
#     expect(Car.count).to eq(3)
#     expect(Motorcycle.count).to eq(1)
#     expect(Part.count).to eq(5)

#     user = User.find_by_email('test@test.test')
#     expect(user).not_to eq(nil)
#   end

#   it "should attach the added serializer method to the user" do
#     user = User.find_by_email('test@test.test')
#     data = user.with_vehicle_parts_serializer

#     expect(data.except('vehicles')).to eq({"id"=>1, "email"=>"test@test.test", "full_name"=>"Ben Dana"})

#     expect(data['vehicles']).to eq(
#       [
#         {"id"=>1, "make"=>"Dodge", "model"=>"Caraven", "parts"=>[
#           {"id"=>1, "name"=>"Engine", "partable_id"=>1, "partable_type"=>"Vehicle", "parts"=>[
#             {"id"=>2, "name"=>"Alternator", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]},
#             {"id"=>3, "name"=>"Radiator", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]},
#             {"id"=>4, "name"=>"Battery", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]}]},
#             {"id"=>5, "name"=>"Frame", "partable_id"=>1, "partable_type"=>"Vehicle", "parts"=>[]}
#           ]
#         },
#         {"id"=>2, "make"=>"Tesla", "model"=>"Roadster", "parts"=>[]},
#         {"id"=>3, "make"=>"Ford", "model"=>"Firebird", "parts"=>[]},
#         {"id"=>4, "make"=>"Honda", "model"=>"Rebel", "parts"=>[]}
#       ]
#     )
#   end

#   it "should attach the added serializer method to the user (with compression)" do
#     allow(Serializer.configuration).to receive(:compress).and_return(true)
#     expect(Serializer.configuration.compress).to eq(true)

#     user = User.find_by_email('test@test.test')
#     data = user.with_vehicle_parts_serializer

#     expect(data.except('vehicles')).to eq({"id"=>1, "email"=>"test@test.test", "full_name"=>"Ben Dana"})

#     expect(data['vehicles']).to eq(
#       [
#         {"id"=>1, "make"=>"Dodge", "model"=>"Caraven", "parts"=>[
#           {"id"=>1, "name"=>"Engine", "partable_id"=>1, "partable_type"=>"Vehicle", "parts"=>[
#             {"id"=>2, "name"=>"Alternator", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]},
#             {"id"=>3, "name"=>"Radiator", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]},
#             {"id"=>4, "name"=>"Battery", "partable_id"=>1, "partable_type"=>"Part", "parts"=>[]}]},
#             {"id"=>5, "name"=>"Frame", "partable_id"=>1, "partable_type"=>"Vehicle", "parts"=>[]}
#           ]
#         },
#         {"id"=>2, "make"=>"Tesla", "model"=>"Roadster", "parts"=>[]},
#         {"id"=>3, "make"=>"Ford", "model"=>"Firebird", "parts"=>[]},
#         {"id"=>4, "make"=>"Honda", "model"=>"Rebel", "parts"=>[]}
#       ]
#     )
#   end

# end