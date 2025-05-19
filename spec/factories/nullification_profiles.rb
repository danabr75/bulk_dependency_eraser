FactoryBot.define do
  factory :nullification_profile do
    bio { Faker::Lorem.sentence }
    user { nil }
    tableoid { NullificationProfile.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless NullificationProfile.exists?(ctid: value)
      end
    end
  end
end