FactoryBot.define do
  factory :text do
    text { Faker::Lorem.sentence }
    user
    tableoid { Text.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Text.exists?(ctid: value)
      end
    end
  end
end