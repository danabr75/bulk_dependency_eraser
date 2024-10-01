require 'rails_helper'

# Using class name instead of class
# - if the class is defined before the 'before' block's ActiveRecord::Base stub, it's non-effective for the builder's DEFAULT_DB_WRAPPER proc definition.
RSpec.describe BulkDependencyEraser::Deleter do
  fixtures(ALL_FIXTURE_TABLES.call)

  let(:model_klass) { User }
  let(:query) { model_klass.where(email: 'test@test.test') }
  let(:params) { { class_names_and_ids: input_deletion_list } }
  subject { described_class.new(**params) }
  let(:do_request) { subject.execute }

  let!(:user) { query.first }
  let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
  let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
  let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
  let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
  let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }

  let(:input_deletion_list) do
    {
      "User" => [user.id],
      "Vehicle" => expected_owned_vehicle_ids.sort,
      "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
    }
  end

  before do
    allow(ActiveRecord::Base).to receive(:connected_to).and_yield

    # We have to recall the class, so that it'll have the stubbed ActiveRecord::Base in it's DEFAULT_DB_WRAPPER proc.
    # - if we didn't, we'd have no way to confirm that ActiveRecord::Base had it's :connected_to method called
    # - suppressing warnings about redefining constants, from the class being loaded in twice
    suppress_output do
      load Rails.root.join('../../lib/bulk_dependency_eraser/deleter.rb')
    end
  end

  context 'using DEFAULT_DB_WRAPPER' do
    it "should execute within a database writing role" do
      do_request

      expect(subject.errors).to be_empty

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :writing).exactly(3).times
    end
  end

  context 'using custom batch_size' do
    let(:params) { super().merge(opts: { batch_size: 1 }) }

    it "should execute within a database writing role" do
      do_request

      expect(subject.errors).to be_empty

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :writing).exactly(14).times
    end
  end
end