FactoryBot.define do
  factory :profile do
    bio { Faker::Lorem.sentence }
    user
  end
end