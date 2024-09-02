FactoryBot.define do
  factory :nullify_registration do
    active { true }
    registerable { nil }
  end
end