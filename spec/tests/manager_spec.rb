require 'rails_helper'

RSpec.describe BulkDependencyEraser::Builder do
  fixtures(ALL_DATABASE_TABLES.call)
  let(:model_klass) { User }
  let(:query) { model_klass.where(email: 'test@test.test') }
  let(:user) { query.first }
  let(:params) { {query:} }
  let(:subject) { described_class.new(**params) }
  let(:do_request) { subject.execute }

  let!(:init_db_snapshot) { get_db_snapshot }

  context "When 'dependency: :destroy' assoc has a join table without an ID column" do
    let(:model_klass) { UserWithIdlessJoinTableDependent }

    it "should raise an error" do
      expect(model_klass.reflect_on_association(:users_vehicles).options[:dependent]).to eq(:destroy)

      aggregate_failures do
        expect(do_request).to be_falsey
        expect(subject.errors).to eq(["#{model_klass.name}'s association 'users_vehicles' - assoc class does not use 'id' as a primary_key"])
      end
    end
  end

  # context "When 'dependency: :destroy' assoc has a through join table without an ID column" do

  context "dependency: :destroy" do
    let(:model_klass) { UserWithHasManyDependent }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }

    let(:expected_db_snapshot_change) do
      {
        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "User" => [user.id],
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end

    it "should destroy successfully" do
      query.destroy_all

      post_action_snapshot = compare_db_snapshot(init_db_snapshot)
      expect(post_action_snapshot[:added]).to eq({})
      expect(post_action_snapshot[:deleted]).to eq(expected_db_snapshot_change)
    end

    it "should mirror the rails destroy" do
      expect(model_klass.reflect_on_association(:owned_vehicles).options[:dependent]).to eq(:destroy)
      expect(user.owned_vehicles.count).to eq(4)

      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
        expect(subject.deletion_list).to eq(
          {
            "Part" => vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids,
            model_klass.name => [user.id],
            "Vehicle" => expected_owned_vehicle_ids
          }
        )
        expect(subject.nullification_list).to eq({})
      end

      # USE in manager rspec
      # post_action_snapshot = compare_db_snapshot(init_db_snapshot)
      # expect(post_action_snapshot[:added]).to eq({})
      # expect(post_action_snapshot[:deleted]).to eq(expected_db_snapshot_change)      
    end
  end

  context "When 'dependency: :destroy' through" do
    # We're expecting the 'UserWithHasManyThroughDependent' to destroy the vehicles, and vehicle dependencies.
    # - not expecting to delete the brands.
    let(:model_klass) { UserWithHasManyThroughDependent }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }

    let(:expected_db_snapshot_change) do
      {
        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "User" => [user.id],
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end

    it "should destroy successfully" do
      query.destroy_all

      post_action_snapshot = compare_db_snapshot(init_db_snapshot)
      expect(post_action_snapshot[:added]).to eq({})
      expect(post_action_snapshot[:deleted]).to eq(expected_db_snapshot_change)
    end

    # KNOWN_FAILING
    it "should mirror the rails destroy" do
      # While the dependent is on the :owned_brands, since it's through: :owned_vehicles, :owned_vehicles will be destroyed
      expect(model_klass.reflect_on_association(:owned_brands).options[:dependent]).to eq(:destroy)
      expect(user.owned_brands.count).to eq(4)

      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
        expect(subject.deletion_list).to eq(
          {
            "Part" => vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids,
            model_klass.name => [user.id],
            "Vehicle" => expected_owned_vehicle_ids
          }
        )
        expect(subject.nullification_list).to eq({})
      end

      post_action_snapshot = compare_db_snapshot(init_db_snapshot)
      expect(post_action_snapshot[:added]).to eq({})
      expect(post_action_snapshot[:deleted]).to eq(expected_db_snapshot_change)
    end
  end

  context 'dependency: :restrict_with_error' do
    let(:model_klass) { UserWithRestrictWithError }

    context "When 'dependency: :restrict_with_error' assoc" do
      it "should raise an error" do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_error)

        aggregate_failures do
          expect(do_request).to be_falsey
          expect(subject.errors).to eq(
            [
              "#{model_klass.name}'s assoc 'probable_family_members' has a 'dependent: :restrict_with_error' set. " \
              "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
            ]
          )
        end
      end
    end

    context "When 'dependency: :restrict_with_error' assoc, with forced option" do
      let(:params) { super().merge(opts: {force_destroy_restricted: true}) }

      it "should not raise an error" do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_error)

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to eq([])
        end
      end
    end
  end

  context 'dependency: :restrict_with_exception' do
    let(:model_klass) { UserWithRestrictWithException }

    context "When 'dependency: :restrict_with_exception' assoc" do
      it "should raise an error" do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_exception)

        aggregate_failures do
          expect(do_request).to be_falsey
          expect(subject.errors).to eq(
            [
              "#{model_klass.name}'s assoc 'probable_family_members' has a 'dependent: :restrict_with_exception' set. " \
              "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
            ]
          )
        end
      end
    end

    context "When 'dependency: :restrict_with_exception' assoc, with forced option" do
      let(:params) { super().merge(opts: {force_destroy_restricted: true}) }

      it "should not raise an error" do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_exception)

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to eq([])
        end
      end
    end
  end

  context "build dependency tree for User (incl. scope without arity)" do
    it "should execute successfully" do
      expect(User.reflect_on_association(:users_vehicles).options[:dependent]).to eq(nil)
      puts "GOT HERE"
      puts User.reflect_on_association(:users_vehicles).options.inspect
      do_request

      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
      end
    end

    it "should populate the 'deletion_list'" do
      do_request

      expect(subject.deletion_list).to eq(
        {
          "User" => [user.id] + user.probable_family_members.where.not(id: user.id).pluck(:id)
        }
      )
    end

    it "should populate the 'nullification_list'" do
      do_request

      expect(subject.nullification_list).to eq(
        {
          "User" => {
            # 3 Users to nullify: Ben Dana, Rob Dana, Ben Franklin
            #
            # Ben Dana, because he's also :similarly_named_users of himself
            # Ben Franklin, because he's a :similarly_named_users of Ben Dana
            # - Ben Franklin will delete Rob Dana, because Rob Dana is a :probable_family_members of Ben Franklin
            # Rob Dana, since he is being deleted, will nillify himself, because he's in his own :similarly_named_users list
            #
            # The only user unaffected is Victor Frankenstein, since he shares no names with the others.
            "first_name" => User.where(first_name: %w[Ben Rob], last_name: %w[Dana Franklin]).order(:created_at).pluck(:id)
          }
        }
      )
      expect(subject.nullification_list.dig("User", "first_name")&.count).to eq(3)
    end
  end
end