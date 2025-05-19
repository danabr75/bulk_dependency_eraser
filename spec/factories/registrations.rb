FactoryBot.define do
  factory :registration do
    active { true }
    registerable { nil }
    tableoid { Registration.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Registration.exists?(ctid: value)
      end
    end
  end
end