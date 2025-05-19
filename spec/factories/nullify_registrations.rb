FactoryBot.define do
  factory :nullify_registration do
    active { true }
    registerable { nil }
    tableoid { NullifyRegistration.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless NullifyRegistration.exists?(ctid: value)
      end
    end
  end
end