FactoryBot.define do
  factory :message do
    message { Faker::Lorem.sentence }
    user { create :user }
    tableoid { Message.table_name }
    ctid do
      loop do
        value = "(#{SecureRandom.random_number(1..100) + 100},#{SecureRandom.random_number(1..100) + 100})"
        break value unless Message.exists?(ctid: value)
      end
    end
  end
end