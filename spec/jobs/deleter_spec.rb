require 'rails_helper'

RSpec.describe BulkDependencyEraser::Deleter do
  fixtures(ALL_DATABASE_TABLES.call)
  let(:model_klass) { User }
  let(:input_deletion_list) { {} }
  let(:query) { model_klass.where(email: 'test@test.test') }
  let!(:user) { query.first }
  let(:params) { { class_names_and_ids: input_deletion_list } }
  let(:subject) { described_class.new(**params) }
  let(:do_request) { subject.execute }

  let!(:init_db_snapshot) { get_db_snapshot }

  it 'user should be present' do
    expect(user).not_to be_nil
  end

  context "dependency: :destroy (nested)" do
    let(:model_klass) { UserWithHasManyDependent }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }

    # Can't get this to raise an error, might be due to the SQL test database.
    context 'with out-of-dependency-order input and enable_invalid_foreign_key_detection: true' do
      let(:params) { super().merge({opts: { enable_invalid_foreign_key_detection: true } } ) }
      let(:input_deletion_list) do
        {
          "User" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "User" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        }
      end


      it "should destroy successfully by rails" do
        query.destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_deletion_list)
      end

      it "should execute and mirror the rails destroy" do
        expect(user.owned_vehicles.count).to eq(4)

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_deletion_list)      
      end
    end
  end
end