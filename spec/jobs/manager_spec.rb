require 'rails_helper'

RSpec.describe BulkDependencyEraser::Manager do
  fixtures(ALL_FIXTURE_TABLES.call)

  let(:model_klass) { raise 'override me!' }
  let!(:query)      { raise 'override me!' }
  let(:params) { { query: } }
  let(:do_request) { subject.execute }
  let!(:init_db_snapshot) { get_db_snapshot }
  let(:subject) { described_class.new(**params) }
  # some tests would be more unreadable if we enforced all association deletions.
  let(:rails_ignore_foreign_key_constraint) { true }

  let(:rails_destroy_all) do
    if rails_ignore_foreign_key_constraint
      ActiveRecord::Base.connection.disable_referential_integrity do
        query.destroy_all
      end
    else
      query.destroy_all
    end
  end


  context 'has_many' do
    let(:model_klass) { User }
    let(:query) { model_klass.where(email: 'test@test.test') }
    let!(:user) { query.first }
    
    let(:params) { { query: } }


    let(:query) { model_klass.where(email: 'test@test.test') }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }
    let!(:users_vehicle_ids)  { UsersVehicle.where(user_id: user.id).pluck(:id) }
    let!(:owner_vehicle_ids)  { UsersVehicle.where(vehicle_id: expected_owned_vehicle_ids).pluck(:id) }

    # BASELINE expected snapshots
    let!(:expected_snapshot_list) do
      {
        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "User" => [user.id],
        "UsersVehicle" => (users_vehicle_ids + owner_vehicle_ids).uniq.sort,
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end
    let!(:expected_deletion_list) do
      {
        # These are here because Car and Motorcyle have their own dependent: :destroy, overlapping the owned_vehicles
        # - we go by class, not table_names
        "Car" => user.owned_cars.pluck(:id).sort,
        "Motorcycle" => user.owned_motorcycles.pluck(:id).sort,

        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "User" => [user.id],
        "UsersVehicle" => (users_vehicle_ids + owner_vehicle_ids).uniq.sort,
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end

    it 'user should be present' do
      expect(user).not_to be_nil
    end

    context "When 'dependency: :destroy' assoc has a join table without an ID column" do
      let(:model_klass) { UserWithIdlessAssoc }
      let!(:locations) { create_list(:location, 5) }
      let!(:join_locations_to_user) { locations.each { |l| user.locations << l } }
      let!(:users_location_ids) { UsersLocation.where(user_id: user.id, location_id: locations)}

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:locations).options[:dependent]).to eq(:destroy)
      end

      it "should raise an error" do
        aggregate_failures do
          expect(do_request).to be_falsey
          expect(subject.errors).to eq(["Builder: #{model_klass.name}'s association 'users_locations' - assoc class does not use 'id' as a primary_key"])
        end
      end
    end

    context "dependency: :destroy (nested, through)" do
      let(:rails_ignore_foreign_key_constraint) { false }

      it "should destroy successfully by rails" do
        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      # WORKING!
      context 'with default options' do
        it 'should have the right association dependencies' do
          expect(model_klass.reflect_on_association(:owned_vehicles).options[:dependent]).to eq(:destroy)
          expect(model_klass.reflect_on_association(:owned_motorcycles).options[:dependent]).to eq(:destroy)
          expect(model_klass.reflect_on_association(:owned_cars).options[:dependent]).to eq(:destroy)
        end

        it "should execute and mirror the rails destroy" do
          expect(user.owned_vehicles.count).to eq(4)

          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to be_empty
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end


        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          do_request

          expect(subject.nullification_list).to eq({})
        end

        it "should not populate the ignore_table lists" do
          do_request

          expect(subject.ignore_table_deletion_list).to eq({})
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end

      context 'with verbose: true' do
        let(:params) { super().merge(opts: { verbose: true }) }

        it "should execute and mirror the rails destroy" do
          expect(user.owned_vehicles.count).to eq(4)

          aggregate_failures do
            # Suppress versbose output
            suppress_stdout do
              expect(do_request).to be_truthy
            end
            expect(subject.errors).to be_empty
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end


        it "should populate the deletion list" do
          suppress_stdout do
            do_request
          end

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          suppress_stdout do
            do_request
          end

          expect(subject.nullification_list).to eq({})
        end

        it "should not populate the ignore_table lists" do
          suppress_stdout do
            do_request
          end

          expect(subject.ignore_table_deletion_list).to eq({})
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end

      context "with ignore_table: ['Vehicle']" do
        let(:params) { super().merge(opts: {ignore_tables: ['vehicles']}) }
        let!(:expected_snapshot_list) do
          snapshot = super()
          snapshot.delete('Vehicle')
          snapshot
        end
        let!(:expected_deletion_list) do
          snapshot = super()
          snapshot.delete('Car')
          snapshot.delete('Motorcycle')
          snapshot.delete('Vehicle')
          snapshot
        end
        let!(:expected_ignore_table_deletion_list) do
          {
            "Car" => user.owned_cars.pluck(:id).sort,
            "Motorcycle" => user.owned_motorcycles.pluck(:id).sort,
            "Vehicle" => expected_owned_vehicle_ids.sort,
          }
        end

        it "should execute successfully" do
          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to be_empty
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end


        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          expect(subject.nullification_list).to eq({})
        end

        it "should populate the ignore_table lists" do
          do_request

          expect(subject.ignore_table_deletion_list).to eq(expected_ignore_table_deletion_list)
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end

      context "with ignore_tables_and_dependencies: ['Vehicle']" do
        let(:params) { super().merge(opts: {ignore_tables_and_dependencies: ['vehicles']}) }
        let!(:expected_snapshot_list) do
          snapshot = super()
          snapshot.delete('Vehicle')
          snapshot.delete('Part')
          snapshot["UsersVehicle"] = users_vehicle_ids.sort
          snapshot
        end
        let(:expected_deletion_list) do
          snapshot = super()
          snapshot.delete('Car')
          snapshot.delete('Motorcycle')
          snapshot.delete('Vehicle')
          snapshot.delete('Part')
          snapshot["UsersVehicle"] = users_vehicle_ids.sort
          snapshot
        end

        it "should execute and mirror the rails destroy" do
          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to be_empty
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end


        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          expect(subject.nullification_list).to eq({})
        end

        it "should not populate the ignore_table lists" do
          do_request

          expect(subject.ignore_table_deletion_list).to eq({})
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end

      context 'with enable_invalid_foreign_key_detection: true' do
        # Have to ignore the join table or else it'll try to delete the vehicles first and get an error
        let(:params) { super().merge(opts: { enable_invalid_foreign_key_detection: true, ignore_tables: ['users_vehicles'] }) }
        let!(:expected_deletion_list) do
          snapshot = super()
          snapshot.delete('UsersVehicle')
          snapshot
        end

        it "should execute and mirror the rails destroy" do
          expect(user.owned_vehicles.count).to eq(4)

          subject.build

          expect(subject.ignore_table_deletion_list).to eq({ 'UsersVehicle' => (users_vehicle_ids + owner_vehicle_ids).uniq.sort })

          # manually delete the join table, in the right sequence
          UsersVehicle.where(id: subject.ignore_table_deletion_list['UsersVehicle']).delete_all

          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to be_empty
          end

          UsersVehicle.where(id: users_vehicle_ids).delete_all

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end

        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          do_request

          expect(subject.nullification_list).to eq({})
        end

        it "should populate the ignore_table lists" do
          do_request

          expect(subject.ignore_table_deletion_list).to eq({ 'UsersVehicle' => (users_vehicle_ids + owner_vehicle_ids).uniq.sort })
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end
    end

    # ALL TESTS ABOVE HERE ARE PASSING!!!

    context 'dependency: :restrict_with_error' do
      let!(:message) { create(:message, user:) }

      context "When 'dependency: :restrict_with_error' assoc" do
        it 'should have the right association dependency' do
          expect(model_klass.reflect_on_association(:messages).options[:dependent]).to eq(:restrict_with_error)
        end

        it "should fail rails destroy" do
          expect(user.destroy).to eq(false)
        end

        it "should report an error" do
          aggregate_failures do
            expect(do_request).to be_falsey
            expect(subject.errors).to eq(
              [
                "Builder: User's assoc 'messages' has a restricted dependency type. " \
                "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
              ]
            )
          end
        end
      end

      context "When 'dependency: :restrict_with_error' (forced option)" do
        # Can't mirror the rails deletion here, since rails won't delete it.
        let(:params) { super().merge(opts: {force_destroy_restricted: true}) }

        let!(:expected_snapshot_list) do
          snapshot = super()
          snapshot = snapshot.to_a.insert(0, ['Message', [message.id]]).to_h
          snapshot
        end
        let!(:expected_deletion_list) do
          snapshot = super()
          snapshot = snapshot.to_a.insert(0, ['Message', [message.id]]).to_h
          snapshot
        end

        it "should execute successfully" do
          updated_db_snapshot = get_db_snapshot
          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to eq([])
          end

          post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)    
        end

        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should execute the nullification list" do
          do_request

          expect(subject.nullification_list).to eq({})
        end
      end
    end


    # ALL WORKING ABOVE HERE
    context 'dependency: :restrict_with_exception' do
      let(:model_klass) { UserWithRestrictWithException }

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_exception)
      end

      context "When 'dependency: :restrict_with_exception' assoc" do
        it "should report an error" do
          aggregate_failures do
            expect(do_request).to be_falsey
            expect(subject.errors).to eq(
              [
                "Builder: #{model_klass.name}'s assoc 'probable_family_members' has a 'dependent: :restrict_with_exception' set. " \
                "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
              ]
            )
          end
        end
      end

      context "When 'dependency: :restrict_with_exception' assoc, with forced option" do
        let(:params) { super().merge(opts: {force_destroy_restricted: true}) }
        let!(:expected_snapshot_list) do
          {
            "User" => ([user.id] + user.probable_family_members.where.not(id: user.id).pluck(:id)).sort
          }
        end
        let!(:expected_deletion_list) do
          {
            "UserWithRestrictWithException" => [user.id],
            "User" => ([user.id] + user.probable_family_members.where.not(id: user.id).pluck(:id)).sort
          }
        end
        let!(:expected_nullification_list) do
          {
            # 3 Users to nullify: Ben Dana, Rob Dana, Ben Franklin
            "User" => {
              # Ben Dana, because he's also :similarly_named_users of himself
              # Ben Franklin, because he's a :similarly_named_users of Ben Dana
              # - Ben Franklin will delete Rob Dana, because Rob Dana is a :probable_family_members of Ben Franklin
              # Rob Dana, since he is being deleted, will nillify himself, because he's in his own :similarly_named_users list
              #
              # The only user unaffected is Victor Frankenstein, since he shares no names with the others.
              "first_name" => User.where(first_name: %w[Ben Rob], last_name: %w[Dana Franklin]).order(:created_at).pluck(:id)
            }
          }
        end

        it 'should have the right association dependency' do
          expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_exception)
        end

        it "should not raise an error" do
          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to eq([])
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)   
        end


        it "should populate the 'deletion_list'" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end


        it "should populate the 'nullification_list'" do
          do_request

          expect(subject.nullification_list).to eq(expected_nullification_list)
          expect(subject.nullification_list.dig("User", "first_name")&.count).to eq(3)


          nullified_user_ids = subject.nullification_list.dig("User", "first_name")
          # some of the nullifieds were deleted
          nullified_user_ids = nullified_user_ids - subject.deletion_list['User']
          # Will be at least one that wasn't deleted: Ben Franklin
          expect(nullified_user_ids.count).to be >= 1

          expect(User.where(id: nullified_user_ids).pluck(:first_name)).to eq([nil])
          expect(User.where(last_name: 'Franklin').pluck(:first_name)).to eq([nil])
        end
      end
    end

    context "build dependency tree for User (incl. scope without arity)" do
      let!(:expected_deletion_list) do
        {
          "User" => ([user.id] + user.probable_family_members.where.not(id: user.id).pluck(:id)).sort
        }
      end
      let!(:expected_nullification_list) do
        {
          # 3 Users to nullify: Ben Dana, Rob Dana, Ben Franklin
          "User" => {
            # Ben Dana, because he's also :similarly_named_users of himself
            # Ben Franklin, because he's a :similarly_named_users of Ben Dana
            # - Ben Franklin will delete Rob Dana, because Rob Dana is a :probable_family_members of Ben Franklin
            # Rob Dana, since he is being deleted, will nillify himself, because he's in his own :similarly_named_users list
            #
            # The only user unaffected is Victor Frankenstein, since he shares no names with the others.
            "first_name" => User.where(first_name: %w[Ben Rob], last_name: %w[Dana Franklin]).order(:created_at).pluck(:id)
          }
        }
      end

      it 'should have the right association dependency' do
        expect(User.reflect_on_association(:users_vehicles).options[:dependent]).to eq(nil)
      end

      it "should execute successfully" do
        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_deletion_list)  
      end

      it "should populate the 'deletion_list'" do
        do_request

        expect(subject.deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the 'nullification_list'" do
        do_request

        expect(subject.nullification_list).to eq(expected_nullification_list)
        expect(subject.nullification_list.dig("User", "first_name")&.count).to eq(3)
      end
    end
  end

  context 'belongs_to' do
    context "dependency: :destroy" do
      let(:model_klass) { Address }
      # TODO CREATE ADDRESS FACTROY
      let!(:query) { model_klass.where(street: '123 Baker St.') }
      let!(:address) { query.first }

      let!(:expected_address_ids) { [address.id] }
      let!(:expected_user_ids)    { [address.user.id] }

      let(:expected_snapshot_list) do
        {
          "User" => [address.user.id].sort,
          "Address" => [address.id].sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "UserWithNoDependents" => [address.user.id].sort,
          "Address" => [address.id].sort,
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:user).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end


      it "should populate the deletion list" do
        do_request

        expect(subject.deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_request

        expect(subject.nullification_list).to eq({})
      end

      it "should not populate the ignore_table lists" do
        do_request

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context "dependency: :destroy (polymorphic)" do
      let(:model_klass) { PartWithDependentPartable }
      let!(:query) { model_klass.where(name: ['Custom Engine', 'Custom Frame']) }
      let!(:vehicle_a) { VehicleWithNoDependents.find_by_model('Civic') }
      let!(:vehicle_b) { VehicleAlsoWithNoDependents.find_by_model('CRV') }
      let!(:part_a) { query.first }
      let!(:part_b) { query.last }

      let!(:expected_part_ids) { [part_a.id, part_b.id] }
      let!(:expected_vehicle_ids) { [vehicle_a.id, vehicle_b.id] }

      context 'with default options' do
        let(:expected_snapshot_list) do
          {
            "Vehicle" => expected_vehicle_ids.sort,
            "Part" => expected_part_ids.sort,
          }
        end
        let(:expected_deletion_list) do
          {
            "VehicleWithNoDependents" => [vehicle_a.id],
            "VehicleAlsoWithNoDependents" => [vehicle_b.id],
            "PartWithDependentPartable" => expected_part_ids.sort,
          }
        end

        it 'should have the right association dependency' do
          expect(model_klass.reflect_on_association(:partable).options[:dependent]).to eq(:destroy)
        end

        it "should destroy successfully by rails" do
          rails_destroy_all

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
        end

        it "should execute and mirror the rails destroy" do
          aggregate_failures do
            expect(do_request).to be_truthy
            expect(subject.errors).to be_empty
          end

          post_action_snapshot = compare_db_snapshot(init_db_snapshot)
          expect(post_action_snapshot[:added]).to eq({})
          expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
        end


        it "should populate the deletion list" do
          do_request

          expect(subject.deletion_list).to eq(expected_deletion_list)
        end

        it "should populate the nullification list" do
          do_request

          expect(subject.nullification_list).to eq({})
        end

        it "should not populate the ignore_table lists" do
          do_request

          expect(subject.ignore_table_deletion_list).to eq({})
          expect(subject.ignore_table_nullification_list).to eq({})
        end
      end
    end
  end

  context 'has_one' do
    context 'dependency: :destroy' do
      let(:model_klass) { UserWithHasOneDependency }
      let!(:query) { model_klass.where(email: 'test5@test.test') }
      # vehicle will have multiple users, but only the one has_one will be destroyed.
      let!(:user) { query.first }
      let!(:profile) { user.profile }

      let(:expected_snapshot_list) do
        {
          "User" => [user.id].sort,
          "Profile" => [profile.id].sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "Profile" => [profile.id].sort,
          "UserWithHasOneDependency" => [user.id].sort,
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:profile).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end


      it "should populate the deletion list" do
        do_request

        expect(subject.deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_request

        expect(subject.nullification_list).to eq({})
      end

      it "should not populate the ignore_table lists" do
        do_request

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    # PENDING
    context 'dependency: :destroy (polymorphic)' do
      let(:model_klass) { VehicleWithHasOnePolymorphicPart }
      
    end
  end

  # TODO:
  # - need to support instantiation where scopes require it.
  # context "build dependency tree for User (incl. scope with arity)" do
end