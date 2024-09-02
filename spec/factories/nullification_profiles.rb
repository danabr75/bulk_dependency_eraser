FactoryBot.define do
  factory :nullification_profile do
    bio { Faker::Lorem.sentence }
    user { nil }
  end
end