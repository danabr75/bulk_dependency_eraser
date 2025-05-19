FactoryBot.define do
  factory :vehicle do
    model { Faker::Vehicle.model }
    rented_by { nil }
    owner { nil }
    brand { nil }
    tableoid { Vehicle.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Vehicle.exists?(ctid: value)
      end
    end
  end

  factory :motorcycle, parent: :vehicle do
    # attributes specific to the subclass
  end
end