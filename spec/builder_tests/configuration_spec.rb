require 'rails_helper'

RSpec.describe "Configuration" do
  it "should have global compression disabled" do
    expect(Serializer.configuration.compress).to eq(false)
  end

  it "should have global debug disabled" do
    expect(Serializer.configuration.debug).to eq(false)
  end

end