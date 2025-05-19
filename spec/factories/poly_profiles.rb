FactoryBot.define do
  factory :poly_profile do
    bio { Faker::Lorem.sentence }
    profilable { nil }
    tableoid { PolyProfile.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless PolyProfile.exists?(ctid: value)
      end
    end
  end
end