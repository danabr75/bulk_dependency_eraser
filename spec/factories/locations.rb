FactoryBot.define do
  factory :location do
    name { Faker::Address.city }
    tableoid { Location.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Location.exists?(ctid: value)
      end
    end
  end
end