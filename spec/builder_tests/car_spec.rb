require 'rails_helper'

RSpec.describe Car do
  fixtures(ALL_DATABASE_TABLES)

  it "All Serializer Queries are available on the Part model." do
    expect(Part.shallow_serializer_query).to eq({
      :include => {},
    })
    expect(Part.serializer_query).to eq(
      {:include=>{:parts=>{:include=>{:parts=>{:include=>{:parts=>{:include=>{:parts=>{:include=>{:parts=>{:include=>{}}}}}}}}}}}}
    )
  end

  it "All Serializer Queries are available on the Car model." do
    expect(Car.without_nested_parts_serializer_query).to eq(    {
      :include => {
        parts: Part.shallow_serializer_query
      },
      :methods => [],
      :except => ["user_id"],
      cache_key: :without_nested_parts_serializer_query,
    })

    expect(Car.serializer_query).to eq({
      :include => {
      },
      :methods => ["make_and_model"],
      :except => ["user_id"],
      cache_key: :serializer_query,
      cache_for: nil,
    })

    expect(Car.with_parts_serializer_query).to eq({
      :include => {
        parts: Part.serializer_query
      },
      :methods => [],
      :except => ["user_id"],
      cache_key: :with_parts_serializer_query,
    })

    expect(Car.uncached_test2_serializer_query).to eq({
      :include => {
      },
      :methods => ["make_and_model"],
      :except => ["user_id"],
    })
  end

  it "should have only 1 query key in it's serializer key cache constant3" do
    expect(Car.singleton_methods.reject{ |v| !v.to_s.ends_with?('serializer_query') }.sort).to eq([
      :without_nested_parts_serializer_query,
      :serializer_query,
      :with_parts_serializer_query,
      :uncached_test2_serializer_query,
    ].sort)
    # got: [:without_nested_parts_serializer_query, :with_parts_serializer_query, :uncached_test2_serializer_query]
  end



  it "should have only 1 query key in it's serializer key cache constant" do
    vehicle = Car.find_by_model("Caraven").serializer
    expect(Car::SERIALIZER_QUERY_KEYS_CACHE.sort).to eq([
      :without_nested_parts_serializer_query,
      :serializer_query,
      :with_parts_serializer_query,
      :uncached_test2_serializer_query
    ].sort)
  end

  it "should have a parent class with 2 query keys in it's serializer key cache constant" do
    expect(Vehicle::SERIALIZER_QUERY_KEYS_CACHE.sort).to eq([:serializer_query, :with_parts_serializer_query, :uncached_test2_serializer_query].sort)
  end

  # it "should have access to it's inherited query keys" do
  #   expect(Car.get_cumulatively_inherited_serializer_query_list).to eq(
  #     [:without_nested_parts_serializer_query, :serializer_query, :with_parts_serializer_query, :uncached_test2_serializer_query]
  #   )
  # end

  # it "should have a parent class with 2 query keys in it's cumulative serializer keys" do
  #   expect(Vehicle.get_cumulatively_inherited_serializer_query_list).to eq(
  #     [:serializer_query, :with_parts_serializer_query, :uncached_test2_serializer_query]
  #   )
  # end

  it "should not be cached when cache_for is nil" do
    vehicle = Car.find_by_model("Caraven")
    expect(vehicle).not_to eq(nil)

    expect(vehicle.serializer).to eq({"id"=>1, "make"=>"Dodge", "model"=>"Caraven", "make_and_model"=>"Dodge Caraven"} )

    vehicle.update_column(:make, "Plymouth")

    expect(vehicle.serializer).to eq({"id"=>1, "make"=>"Plymouth", "model"=>"Caraven", "make_and_model"=>"Plymouth Caraven"} )
  end

  it "should not be cached when cache_key is nil" do
    vehicle = Car.find_by_model("Caraven")
    expect(vehicle).not_to eq(nil)

    expect(vehicle.uncached_test2_serializer).to eq({"id"=>1, "make"=>"Dodge", "model"=>"Caraven", "make_and_model"=>"Dodge Caraven"} )

    vehicle.update(make: "Plymouth")

    expect(vehicle.uncached_test2_serializer).to eq({"id"=>1, "make"=>"Plymouth", "model"=>"Caraven", "make_and_model"=>"Plymouth Caraven"} )
  end
end