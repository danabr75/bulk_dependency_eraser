FactoryBot.define do
  factory :text do
    text { Faker::Lorem.sentence }
    user { create :user }
  end
end