FactoryBot.define do
  factory :vehicle do
    model { Faker::Vehicle.model }
    rented_by { nil }
    owner { nil }
    brand { nil }
  end

  factory :motorcycle, parent: :vehicle do
    # attributes specific to the subclass
  end
end