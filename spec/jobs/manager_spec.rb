require 'rails_helper'

RSpec.describe BulkDependencyEraser::Manager do
  fixtures(ALL_DATABASE_TABLES.call)
  let(:model_klass) { User }
  let(:query) { model_klass.where(email: 'test@test.test') }
  let!(:user) { query.first }
  let(:params) { {query:} }
  let(:subject) { described_class.new(**params) }
  let(:do_request) { subject.execute }

  let!(:init_db_snapshot) { get_db_snapshot }

  it 'user should be present' do
    expect(user).not_to be_nil
  end

  context "When 'dependency: :destroy' assoc has a join table without an ID column" do
    let(:model_klass) { UserWithIdlessJoinTableDependent }


    it 'should have the right association dependency' do
      expect(model_klass.reflect_on_association(:users_vehicles).options[:dependent]).to eq(:destroy)
    end

    it "should raise an error" do
      aggregate_failures do
        expect(do_request).to be_falsey
        expect(subject.errors).to eq(["Builder: #{model_klass.name}'s association 'users_vehicles' - assoc class does not use 'id' as a primary_key"])
      end
    end
  end

  context "dependency: :destroy (nested)" do
    let(:model_klass) { UserWithHasManyDependent }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }
    context 'with default options' do
      let(:expected_snapshot_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "User" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "UserWithHasManyDependent" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:owned_vehicles).options[:dependent]).to eq(:destroy)
      end


      it "should destroy successfully by rails" do
        query.destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
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
      let(:expected_snapshot_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "User" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "UserWithHasManyDependent" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:owned_vehicles).options[:dependent]).to eq(:destroy)
      end


      it "should destroy successfully by rails" do
        query.destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
      end

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
      let(:expected_snapshot_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "User" => [user.id],
        }
      end
      let(:expected_deletion_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "UserWithHasManyDependent" => [user.id],
        }
      end
      let(:expected_ignore_table_deletion_list) do
        {
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
      let(:expected_snapshot_list) do
        {
          "User" => [user.id],
        }
      end
      let(:expected_deletion_list) do
        {
          "UserWithHasManyDependent" => [user.id],
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

      it "should not populate the ignore_table lists" do
        do_request

        expect(subject.ignore_table_deletion_list).to eq({})
        expect(subject.ignore_table_nullification_list).to eq({})
      end
    end

    context 'with enable_invalid_foreign_key_detection: true' do
      let(:params) { super().merge(opts: { enable_invalid_foreign_key_detection: true }) }
      let(:expected_snapshot_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "User" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end
      let(:expected_deletion_list) do
        {
          "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
          "UserWithHasManyDependent" => [user.id],
          "Vehicle" => expected_owned_vehicle_ids.sort,
        }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:owned_vehicles).options[:dependent]).to eq(:destroy)
      end

      it "should destroy successfully by rails" do
        query.destroy_all

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
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
  end

  context "When 'dependency: :destroy' (through)" do
    # We're expecting the 'UserWithHasManyThroughDependent' to destroy the vehicles, and vehicle dependencies.
    # - not expecting to delete the brands.
    let(:model_klass) { UserWithHasManyThroughDependent }

    let!(:expected_owned_vehicle_ids) { user.owned_vehicles.pluck(:id) }
    let!(:vehicle_part_ids)   { Part.where(partable_type: 'Vehicle', partable_id: expected_owned_vehicle_ids).pluck(:id) }
    let!(:nested_parts_a_ids) { Part.where(partable_type: 'Part', partable_id: vehicle_part_ids).pluck(:id) }
    let!(:nested_parts_b_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_a_ids).pluck(:id) }
    let!(:nested_parts_c_ids) { Part.where(partable_type: 'Part', partable_id: nested_parts_b_ids).pluck(:id) }

    let(:expected_deletion_list) do
      {
        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "UserWithHasManyThroughDependent" => [user.id],
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end
    let(:expected_snapshot_list) do
      {
        "Part" => (vehicle_part_ids + nested_parts_a_ids + nested_parts_b_ids + nested_parts_c_ids).sort,
        "User" => [user.id],
        "Vehicle" => expected_owned_vehicle_ids.sort,
      }
    end

    it 'should have the right association dependency' do
      # While the dependent is on the :owned_brands, since it's through: :owned_vehicles, :owned_vehicles will be destroyed
      expect(model_klass.reflect_on_association(:owned_brands).options[:dependent]).to eq(:destroy)
    end

    it "should destroy successfully by rails" do
      query.destroy_all

      post_action_snapshot = compare_db_snapshot(init_db_snapshot)
      expect(post_action_snapshot[:added]).to eq({})
      expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)
    end

    it "should execute and mirror the rails destroy" do
      expect(user.owned_brands.count).to eq(4)

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
  end

  context 'dependency: :restrict_with_error' do
    let(:model_klass) { UserWithRestrictWithError }

    context "When 'dependency: :restrict_with_error' assoc" do
      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_error)
      end

      it "should report an error" do
        aggregate_failures do
          expect(do_request).to be_falsey
          expect(subject.errors).to eq(
            [
              "Builder: #{model_klass.name}'s assoc 'probable_family_members' has a 'dependent: :restrict_with_error' set. " \
              "If you still wish to destroy, use the 'force_destroy_restricted: true' option"
            ]
          )
        end
      end
    end

    context "When 'dependency: :restrict_with_error' assoc, with forced option" do
      # Can't mirror the rails deletion here, since rails won't delete it.
      let(:params) { super().merge(opts: {force_destroy_restricted: true}) }
      let(:user_ids_with_similar_last_names) { model_klass.where(last_name) }
      let!(:expected_deletion_list) do
        {
          "UserWithRestrictWithError" => [user.id],
          "User" => ([user.id] + User.where.not(id: user.id).where(last_name: user.last_name).pluck(:id)).sort,
        }
      end
      let!(:expected_snapshot_list) do
        {
          "User" => ([user.id] + User.where.not(id: user.id).where(last_name: user.last_name).pluck(:id).sort),
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
              "first_name" => User.where(first_name: %w[Ben Rob], last_name: %w[Dana Franklin]).pluck(:id).sort
            },
          }
      end

      it 'should have the right association dependency' do
        expect(model_klass.reflect_on_association(:probable_family_members).options[:dependent]).to eq(:restrict_with_error)
      end

      it "should execute successfully" do
        aggregate_failures do
          expect(do_request).to be_truthy
          expect(subject.errors).to eq([])
        end

        post_action_snapshot = compare_db_snapshot(init_db_snapshot)
        expect(post_action_snapshot[:added]).to eq({})
        expect(post_action_snapshot[:deleted]).to eq(expected_snapshot_list)    
      end

      it "should populate the deletion list" do
        do_request

        expect(subject.deletion_list).to eq(expected_deletion_list)
      end

      it "should execute the nullification list" do
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

  # TODO:
  # - need to support instantiation where scopes require it.
  # context "build dependency tree for User (incl. scope with arity)" do
end