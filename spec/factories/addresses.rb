FactoryBot.define do
  factory :address do
    street { Faker::Address.street_name }
    user
    tableoid { Address.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Address.exists?(ctid: value)
      end
    end
  end
end