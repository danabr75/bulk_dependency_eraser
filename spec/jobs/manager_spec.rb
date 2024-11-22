require 'rails_helper'

RSpec.describe BulkDependencyEraser::Manager do
  fixtures(ALL_FIXTURE_TABLES.call)

  let(:model_klass) { raise 'override me!' }
  let!(:query)      { raise 'override me!' }
  let(:params) do
    p = { query: }
    p[:opts] = opts if !opts.nil?
    p
  end
  let(:opts) { nil }
  let(:do_request) { subject.execute }
  let(:do_build) { subject.build }
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

  # Sort the IDs so that we can more easily compare against snapshot
  let(:sorted_deletion_list) { subject.deletion_list.transform_values { |array| array.sort } }
  let(:sorted_nullification_list) do
    subject.nullification_list.transform_values do |inner_hash|
      inner_hash.transform_values { |array| array.sort }
    end
  end

  # List of options that we can check that won't effect the rspec expectations
  # - any options that would change the results have to be checked in their own custom rspec contexts
  options = [
    nil,
    { batch_size: 1 },
    { read_batch_size: 1, delete_batch_size: 1, nullify_batch_size: 1 },
    {
      db_read_wrapper:    ->(block) { block.call },
      db_nullify_wrapper: ->(block) { block.call },
      db_delete_wrapper:  ->(block) { block.call },
    },
    { query_modifier: ->(query) { query.limit(1_000_000)  } },
    { query_modifier: ->(query) { query.limit(1)  } },
    { disable_batching: true },
    { disable_read_batching: true },
    { disable_nullify_batching: true },
    { disable_delete_batching: true },
    {
      disable_batching: true,
      disable_read_batching: true,
      disable_nullify_batching: true,
      disable_delete_batching: true
    },
    { reading_proc_scopes_per_class_name:       { 'User' => ->(query) { query.order(id: :desc) } } },
    { deletion_proc_scopes_per_class_name:      { 'User' => ->(query) { query.order(id: :desc) } } },
    { nullification_proc_scopes_per_class_name: { 'User' => ->(query) { query.order(id: :desc) } } },
    {
      proc_scopes_per_class_name:               { 'User' => ->(query) { query.order(id: :desc) } },
      reading_proc_scopes_per_class_name:       { 'User' => ->(query) { query.order(id: :desc) } },
      deletion_proc_scopes_per_class_name:      { 'User' => ->(query) { query.order(id: :desc) } },
      nullification_proc_scopes_per_class_name: { 'User' => ->(query) { query.order(id: :desc) } },
    },
    { proc_scopes: ->(klass) { nil } }, # non-effective, just testing that it'll accept it
    { proc_scopes: ->(klass) { klass } }, # non-effective, just testing that it'll accept it
    {
      db_delete_all_wrapper: ->(block) {
        ActiveRecord::Base.transaction do
          begin
            block.call # execute deletions
          rescue StandardError => e
            report_error("Issue attempting to delete '#{current_class_name}': #{e.class.name} - #{e.message}")
            raise ActiveRecord::Rollback
          end
        end
      },
      db_nullify_all_wrapper: ->(block) {
        ActiveRecord::Base.transaction do
          begin
            block.call # execute nullifications
          rescue StandardError => e
            report_error("Issue attempting to nullify '#{current_class_name}': #{e.class.name} - #{e.message}")
            raise ActiveRecord::Rollback
          end
        end
      }
    },
  ]
  options.each do |option_set|
    context "with options: #{option_set.nil? ? 'nil' : option_set}" do
      context 'has_many' do
        let(:model_klass) { User }
        let(:query) {
          q = model_klass.where(email: 'test@test.test')
          if option_set&.dig(:query_modifier)
            q = option_set[:query_modifier].call(q)
          end
          q
        }
        let!(:user) { query.first }
        let(:opts) { option_set.nil? ? {} : option_set.except(:query_modifier) }

        let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
        let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
        let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
        let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
        let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }
        let!(:users_vehicle_ids)  { UsersVehicle.where(user_id: user.id).pluck(:id) }
        let!(:owner_vehicle_ids)  { UsersVehicle.where(vehicle_id: expected_owned_vehicle_ids).pluck(:id) }

        # BASELINE expected snapshot/deletion list, when deleting the 'user'
        # Snapshot list will NOT have subclasses, only classes that correspond to a table_name
        let!(:expected_snapshot_list) do
          {
            "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
            "User" => [user.id],
            "UsersVehicle" => (users_vehicle_ids + owner_vehicle_ids).uniq.sort,
            "Vehicle" => expected_owned_vehicle_ids.sort,
          }
        end
        # Deletion list will have subclasses
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
        let!(:expected_nullification_list) do
          {}
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

        context "dependency: :destroy (nested, through, with foreign_key constraint)" do
          let(:rails_ignore_foreign_key_constraint) { false }

          it "should destroy successfully by rails" do
            rails_destroy_all

            post_action_snapshot = compare_db_snapshot(init_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
          end

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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should populate the nullification list" do
              do_build

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end

            it "should not populate the ignore_table lists" do
              do_build

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
                do_build
              end

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should populate the nullification list" do
              suppress_stdout do
                do_build
              end

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end

            it "should not populate the ignore_table lists" do
              suppress_stdout do
                do_build
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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should populate the nullification list" do
              do_build

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end

            it "should populate the ignore_table lists" do
              do_build

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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should populate the nullification list" do
              do_build

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end

            it "should not populate the ignore_table lists" do
              do_build

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

              expect(subject.ignore_table_deletion_list).to eq({ 'UsersVehicle' => (users_vehicle_ids.sort + owner_vehicle_ids.sort).uniq })

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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should populate the nullification list" do
              do_build

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end

            it "should populate the ignore_table lists" do
              do_build

              expect(subject.ignore_table_deletion_list).to eq({ 'UsersVehicle' => (users_vehicle_ids.sort + owner_vehicle_ids.sort).uniq })
              expect(subject.ignore_table_nullification_list).to eq({})
            end
          end
        end

        context "dependency: :destroy (polymorphic)" do
          let!(:registration_list) { create_list(:registration, 5, registerable: user)} 
          let!(:registration_ids) { registration_list.map(&:id).sort } 
          let!(:expected_snapshot_list) do
            snapshot = super()
            snapshot = snapshot.to_a.insert(0, ['Registration', registration_ids]).to_h
            snapshot
          end
          let!(:expected_deletion_list) do
            snapshot = super()
            snapshot = snapshot.to_a.insert(0, ['Registration', registration_ids]).to_h
            snapshot
          end

          it 'should have the right association dependencies' do
            expect(model_klass.reflect_on_association(:registrations).options[:dependent]).to eq(:destroy)
            expect(model_klass.reflect_on_association(:registrations).options[:as]).to eq(:registerable)
          end

          # Rails bug!
          it "should destroy successfully by rails (failure!, rails can't handle circular dependencies with polymorphism!)" do
            updated_db_snapshot = get_db_snapshot

            rails_destroy_all

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq({})
          end

          it "should execute and mirror the rails destroy (were it successful)" do
            updated_db_snapshot = get_db_snapshot

            aggregate_failures do
              expect(do_request).to be_truthy
              expect(subject.errors).to be_empty
            end

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
          end


          it "should populate the deletion list" do
            do_build

            expect(sorted_deletion_list).to eq(expected_deletion_list)
          end

          it "should populate the nullification list" do
            do_build

            expect(sorted_nullification_list).to eq(expected_nullification_list)
          end

          it "should not populate the ignore_table lists" do
            do_build

            expect(subject.ignore_table_deletion_list).to eq({})
            expect(subject.ignore_table_nullification_list).to eq({})
          end
        end

        context "dependency: :nullify (polymorphic)" do
          let!(:nullify_registration_list) { create_list(:nullify_registration, 5, registerable: user)} 
          let!(:nullify_registration_ids) { nullify_registration_list.map(&:id).sort } 
          let!(:expected_nullification_list) do
            {
              'NullifyRegistration' => {
                'registerable_id' => nullify_registration_ids,
                'registerable_type' => nullify_registration_ids,
              }
            }
          end

          it 'should have the right association dependencies' do
            expect(model_klass.reflect_on_association(:nullify_registrations).options[:dependent]).to eq(:nullify)
            expect(model_klass.reflect_on_association(:nullify_registrations).options[:as]).to eq(:registerable)
          end

          # Rails bug!
          it "should destroy successfully by rails (failure!, rails can't handle circular dependencies with polymorphism!)" do
            updated_db_snapshot = get_db_snapshot

            rails_destroy_all

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
          end

          it "should execute and mirror the rails destroy (were it successful)" do
            updated_db_snapshot = get_db_snapshot

            aggregate_failures do
              expect(do_request).to be_truthy
              expect(subject.errors).to be_empty
            end

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
          end


          it "should populate the deletion list" do
            do_build

            expect(sorted_deletion_list).to eq(expected_deletion_list)
          end

          it "should populate the nullification list" do
            do_build

            expect(sorted_nullification_list).to eq(expected_nullification_list)
          end

          it "should not populate the ignore_table lists" do
            do_build

            expect(subject.ignore_table_deletion_list).to eq({})
            expect(subject.ignore_table_nullification_list).to eq({})
          end
        end

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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should execute the nullification list" do
              do_request

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end
          end
        end

        context 'dependency: :restrict_with_exception' do
          let!(:text) { create(:text, user:) }

          context "When 'dependency: :restrict_with_error' assoc" do
            it 'should have the right association dependency' do
              expect(model_klass.reflect_on_association(:texts).options[:dependent]).to eq(:restrict_with_exception)
            end

            it "should fail rails destroy" do
              expect{ user.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
            end

            it "should report an error" do
              aggregate_failures do
                expect(do_request).to be_falsey
                expect(subject.errors).to eq(
                  [
                    "Builder: User's assoc 'texts' has a restricted dependency type. " \
                    "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
                  ]
                )
              end
            end
          end

          context "When 'dependency: :restrict_with_exception' (forced option)" do
            # Can't mirror the rails deletion here, since rails won't delete it.
            let(:params) { super().merge(opts: {force_destroy_restricted: true}) }

            let!(:expected_snapshot_list) do
              snapshot = super()
              snapshot = snapshot.to_a.insert(0, ['Text', [text.id]]).to_h
              snapshot
            end
            let!(:expected_deletion_list) do
              snapshot = super()
              snapshot = snapshot.to_a.insert(0, ['Text', [text.id]]).to_h
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
              do_build

              expect(sorted_deletion_list).to eq(expected_deletion_list)
            end

            it "should execute the nullification list" do
              do_request

              expect(sorted_nullification_list).to eq(expected_nullification_list)
            end
          end
        end

        context "dependency: :nullify (scope without arity, primary_key other than ID)" do
          let!(:nullify_user_ids) do
            query = User.where.not(id: user.id).limit(2)
            # Update those random 2 users
            query.update_all(last_name: user.first_name)
            ids = query.pluck(:id)
            # Confirm we have 2
            expect(ids).to have_attributes(size: 2)
            ids
          end

          let!(:expected_nullification_list) do
            {
              "User" => {
                "last_name" => nullify_user_ids.sort
              }
            }
          end

          it 'should have the right association dependency' do
            expect(User.reflect_on_association(:people_who_have_my_first_name_as_a_last_name).options[:dependent]).to eq(:nullify)
            expect(User.where(id: nullify_user_ids).pluck(:last_name)).to eq([user.first_name] * 2)
            expect(user.people_who_have_my_first_name_as_a_last_name.count).to eq(2)
          end

          it "should destroy and nullify successfully by rails" do
            rails_destroy_all

            expect(User.where(id: nullify_user_ids).pluck(:last_name)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(init_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
          end

          it "should execute successfully" do
            aggregate_failures do
              expect(do_request).to be_truthy
              expect(subject.errors).to be_empty
            end

            expect(User.where(id: nullify_user_ids).pluck(:last_name)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(init_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)  
          end

          it "should populate the 'deletion_list'" do
            do_build

            expect(sorted_deletion_list).to eq(expected_deletion_list)
          end

          it "should populate the 'nullification_list'" do
            do_build

            expect(sorted_nullification_list).to eq(expected_nullification_list)
          end
        end

        context "dependency: :nullify (no scope, primary_key other than ID)" do
          let!(:nullify_user_ids) do
            query = User.where.not(id: user.id).limit(2)
            # Update those random 2 users
            query.update_all(first_name: user.last_name)
            ids = query.pluck(:id)
            # Confirm we have 2
            expect(ids).to have_attributes(size: 2)
            ids
          end

          let!(:expected_nullification_list) do
            {
              "User" => {
                "first_name" => nullify_user_ids.sort
              }
            }
          end

          it 'should have the right association dependency' do
            expect(User.reflect_on_association(:people_who_have_my_last_name_as_a_first_name).options[:dependent]).to eq(:nullify)
            expect(User.where(id: nullify_user_ids).pluck(:first_name)).to eq([user.last_name] * 2)
            expect(user.people_who_have_my_last_name_as_a_first_name.count).to eq(2)
          end

          it "should destroy and nullify successfully by rails" do
            rails_destroy_all

            expect(User.where(id: nullify_user_ids).pluck(:first_name)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(init_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
          end

          it "should execute successfully" do
            aggregate_failures do
              expect(do_request).to be_truthy
              expect(subject.errors).to be_empty
            end

            expect(User.where(id: nullify_user_ids).pluck(:first_name)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(init_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)  
          end

          it "should populate the 'deletion_list'" do
            do_build

            expect(sorted_deletion_list).to eq(expected_deletion_list)
          end

          it "should populate the 'nullification_list'" do
            do_build

            expect(sorted_nullification_list).to eq(expected_nullification_list)
          end
        end

        context "dependency: :nullify (no scope)" do
          let(:rented_vehicle)    { create(:vehicle, rented_by: user)}
          let(:rented_motorcycle) { create(:motorcycle, rented_by: user)}
          let!(:nullify_vehicle_ids) do
            [rented_vehicle.id, rented_motorcycle.id].sort
          end

          let!(:expected_nullification_list) do
            {
              "Vehicle" => {
                "rented_by_id" => [rented_vehicle.id, rented_motorcycle.id].sort
              }
            }
          end

          it 'should have the right association dependency' do
            expect(User.reflect_on_association(:rented_vehicles).options[:dependent]).to eq(:nullify)
            expect(user.rented_vehicles.count).to eq(2)
          end

          it "should destroy and nullify successfully by rails" do
            updated_db_snapshot = get_db_snapshot

            rails_destroy_all

            expect(Vehicle.where(id: nullify_vehicle_ids).pluck(:rented_by_id)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
          end

          it "should execute successfully" do
            updated_db_snapshot = get_db_snapshot

            aggregate_failures do
              expect(do_request).to be_truthy
              expect(subject.errors).to be_empty
            end

            expect(Vehicle.where(id: nullify_vehicle_ids).pluck(:rented_by_id)).to all(be_nil)

            post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
            expect(post_action_snapshot[:added]).to eq({})
            expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)  
          end

          it "should populate the 'deletion_list'" do
            do_build

            expect(sorted_deletion_list).to eq(expected_deletion_list)
          end

          it "should populate the 'nullification_list'" do
            do_build

            expect(sorted_nullification_list).to eq(expected_nullification_list)
          end
        end
      end
    end
  end

  context 'has_many (custom scope)' do
    let(:model_klass) { User }
    let(:query) { model_klass }
    let!(:user) { User.where(email: 'test6@test.test').first }
    let(:opts) { { proc_scopes_per_class_name: { 'User' => ->(query) { query.limit(1).order(id: :desc) } } } }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }
    let!(:users_vehicle_ids)  { UsersVehicle.where(user_id: user.id).pluck(:id) }
    let!(:owner_vehicle_ids)  { UsersVehicle.where(vehicle_id: expected_owned_vehicle_ids).pluck(:id) }

    # BASELINE expected snapshot/deletion list, when deleting the 'user'
    # Snapshot list will NOT have subclasses, only classes that correspond to a table_name
    let!(:expected_snapshot_list) do
      {
        "User" => [user.id],
      }
    end
    # Deletion list will have subclasses
    let!(:expected_deletion_list) do
      {
        "User" => [user.id],
      }
    end
    let!(:expected_nullification_list) do
      {}
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

  end

  context 'belongs_to' do
    context "dependency: :destroy" do
      let!(:model_klass) { Address }
      let!(:address) { create(:address) }
      let!(:user) { address.user }
      let!(:query) { model_klass.where(street: address.street) }

      let!(:expected_address_ids) { [address.id] }
      let!(:expected_user_ids)    { [address.user.id] }

      let(:expected_snapshot_list) do
        {
          "User" => [user.id].sort,
          "Address" => [address.id].sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "User" => [user.id].sort,
          "Address" => [address.id].sort,
        }
      end
      let!(:expected_nullification_list) do
        {}
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:user).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    # Invalid structure use-case
    # context 'dependency: :nullify'

    context "dependency: :destroy (polymorphic)" do
      let(:model_klass) { Registration }
      let!(:user)    { create(:user) }
      let!(:vehicle) { create(:vehicle) }
      let!(:registration_a) { create(:registration, registerable: user) }
      let!(:registration_b) { create(:registration, registerable: vehicle) }
      let!(:query) { model_klass.where(id: expected_registration_ids).order(:id) }
      let!(:expected_registration_ids) { [registration_a.id, registration_b.id].sort }

      let!(:expected_snapshot_list) do
        {
          "User" => [user.id],
          "Vehicle" => [vehicle.id],
          "Registration" => expected_registration_ids,
        }
      end
      let!(:expected_deletion_list) do
        {
          "User" => [user.id],
          "Vehicle" => [vehicle.id],
          "Registration" => expected_registration_ids,
        }
      end
      let!(:expected_nullification_list) { {} }

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:registerable).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end


      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end
  end

  context 'has_one' do
    context 'dependency: :destroy' do
      let(:model_klass) { User }
      let!(:user) { create(:user) }
      let!(:profile) { create(:profile, user:) }
      let!(:query) { model_klass.where(id: user.id) }

      let!(:expected_snapshot_list) do
        {
          "Profile" => [profile.id],
          "User" => [user.id],
        }
      end
      let!(:expected_deletion_list) do
        {
          "Profile" => [profile.id],
          "User" => [user.id],
        }
      end
      let!(:expected_nullification_list) { {} }

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:profile).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context 'dependency: :nullify' do
      let(:model_klass) { User }
      let!(:user) { create(:user) }
      let!(:nullification_profile) { create(:nullification_profile, user:) }
      let!(:query) { model_klass.where(id: user.id) }

      let!(:expected_snapshot_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_deletion_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_nullification_list) do
        {
          "NullificationProfile" => {
            "user_id" => [nullification_profile.id]
          }
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:nullification_profile).options[:dependent]).to eq(:nullify)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context 'dependency: :destroy (polymorphic)' do
      let(:model_klass) { User }
      let!(:user) { create(:user) }
      let!(:poly_profile) { create(:poly_profile, profilable: user) }
      let!(:query) { model_klass.where(id: user.id) }

      let!(:expected_snapshot_list) do
        {
          "PolyProfile" => [poly_profile.id],
          "User" => [user.id],
        }
      end
      let!(:expected_deletion_list) do
        {
          "PolyProfile" => [poly_profile.id],
          "User" => [user.id],
        }
      end
      let!(:expected_nullification_list) { {} }

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:poly_profile).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context 'dependency: :nullify (polymorphic)' do
      let(:model_klass) { User }
      let!(:user) { create(:user) }
      let!(:nullify_poly_profile) { create(:nullify_poly_profile, profilable: user) }
      let!(:query) { model_klass.where(id: user.id) }

      let!(:expected_snapshot_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_deletion_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_nullification_list) do
        {
          "NullifyPolyProfile" => {
            "profilable_id" => [nullify_poly_profile.id],
            "profilable_type" => [nullify_poly_profile.id],
          }
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:nullify_poly_profile).options[:dependent]).to eq(:nullify)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context 'dependency: :nullify (polymorphic, without general batching)' do
      let(:model_klass) { User }
      let!(:user) { create(:user) }
      let!(:nullify_poly_profile) { create(:nullify_poly_profile, profilable: user) }
      let!(:query) { model_klass.where(id: user.id) }
      let(:opts) { { disable_batching: true } }

      let!(:expected_snapshot_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_deletion_list) do
        {
          "User" => [user.id],
        }
      end
      let!(:expected_nullification_list) do
        {
          "NullifyPolyProfile" => {
            "profilable_id" => [nullify_poly_profile.id],
            "profilable_type" => [nullify_poly_profile.id],
          }
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:nullify_poly_profile).options[:dependent]).to eq(:nullify)
      end

      it "should destroy successfully by rails" do
        updated_db_snapshot = get_db_snapshot

        rails_destroy_all

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

      it "should execute and mirror the rails destroy" do
        updated_db_snapshot = get_db_snapshot

        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to be_empty
        end

        post_action_snapshot = compare_db_snapshot(updated_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)      
      end

      it "should populate the deletion list" do
        do_build

        expect(sorted_deletion_list).to eq(expected_deletion_list)
      end

      it "should populate the nullification list" do
        do_build

        expect(sorted_nullification_list).to eq(expected_nullification_list)
      end

      it "should not populate the ignore_table lists" do
        do_build

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end
  end

  context 'has_many (custom delete_wrapper)' do
    let(:model_klass) { User }
    let(:query) { model_klass }
    before { @delete_proc_run_count = 0 }
    let(:opts) do
      {
        db_delete_wrapper: lambda do |block|
          result, query, ids = block.call
          expect(result).to be_a(Integer)
          # We deleted all vehicles as part of their sub-classes
          # - None are left when we get to deleting Vehicle
          # expect(result).to be > 0
          expect(query).to be_a(ActiveRecord::Relation)
          expect(ids).to be_a(Array)
          expect(ids.count).to be > 0
          @delete_proc_run_count += 1
        end
      }
    end

    it "should execute successfully" do
      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
        expect(@delete_proc_run_count).to eq(6)
        expect(@delete_proc_run_count).to eq(subject.deletion_list.keys.count)
      end 
    end
  end

  context 'has_many (custom nullify_wrapper)' do
    let(:model_klass) { User }
    let!(:user) { query.order(:created_at).first }
    let(:query) { model_klass }
    # Necessary to have nullifiable associations
    let!(:nullify_user_ids) do
      query = User.where.not(id: user.id).limit(2)
      # Update those random 2 users
      query.update_all(last_name: user.first_name)
      ids = query.pluck(:id)
      # Confirm we have 2
      expect(ids).to have_attributes(size: 2)
      ids
    end
    before { @nullify_proc_run_count = 0 }
    let(:opts) do
      {
        db_nullify_wrapper: lambda do |block|
          result, query, ids, nullify_columns_query_value = block.call
          expect(result).to be_a(Integer)
          expect(result).to be > 0
          expect(query).to be_a(ActiveRecord::Relation)
          expect(ids).to be_a(Array)
          expect(ids.count).to be > 0

          expect(nullify_columns_query_value).to be_a(Hash)
          expect(User.column_names).to include(*nullify_columns_query_value.keys)
          expect(nullify_columns_query_value.values.flatten.uniq).to eq([nil])

          @nullify_proc_run_count += 1
        end
      }
    end


    it "should execute successfully" do
      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
        expect(@nullify_proc_run_count).to eq(2)
        expect(@nullify_proc_run_count).to eq(subject.nullification_list['User'].keys.count)
      end 
    end
  end

  # TODO scope instantiation!:
  # - need to support instantiation where scopes require it.
end