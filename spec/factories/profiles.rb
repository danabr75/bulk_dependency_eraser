FactoryBot.define do
  factory :profile do
    bio { Faker::Lorem.sentence }
    user
    tableoid { Profile.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Profile.exists?(ctid: value)
      end
    end
  end
end