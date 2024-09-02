FactoryBot.define do
  factory :message do
    message { Faker::Lorem.sentence }
    user { create :user }
  end
end