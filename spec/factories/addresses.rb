FactoryBot.define do
  factory :address do
    street { Faker::Address.street_name }
    user
  end
end