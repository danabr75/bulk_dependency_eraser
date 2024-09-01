require 'rails_helper'

# Using class name instead of class
# - if the class is defined before the 'before' block's ActiveRecord::Base stub, it's non-effective for the builder's DEFAULT_DB_WRAPPER proc definition.
RSpec.describe BulkDependencyEraser::Nullifier do
  fixtures(ALL_DATABASE_TABLES.call)
  let(:model_klass) { User }
  let(:query) { model_klass.where(email: 'test@test.test') }
  let(:params) { { class_names_columns_and_ids: input_nullification_list } }
  subject { described_class.new(**params) }
  let(:do_request) { subject.execute }

  let!(:input_nullification_list) do
      {
        # 3 Users to nullify: Ben Dana, Rob Dana, Ben Franklin
        "User" => {
          # Ben Dana, because he's also :similarly_named_users of himself
          # Ben Franklin, because he's a :similarly_named_users of Ben Dana
          # - Ben Franklin will delete Rob Dana, because Rob Dana is a :probable_family_members of Ben Franklin
          # Rob Dana, since he is being deleted, will nillify himself, because he's in his own :similarly_named_users list
          #
          # The only user unaffected is Victor Frankenstein, since he shares no names with the others.
          "first_name" => User.where(first_name: %w[Ben Rob]).pluck(:id).sort
        },
        "Part" => {
          "name" => Part.where(name: 'Alternator').pluck(:id).sort
        },
      }
  end

  before do
    allow(ActiveRecord::Base).to receive(:connected_to).and_yield

    # We have to recall the class, so that it'll have the stubbed ActiveRecord::Base in it's DEFAULT_DB_WRAPPER proc.
    # - if we didn't, we'd have no way to confirm that ActiveRecord::Base had it's :connected_to method called
    # - suppressing warnings about redefining constants, from the class being loaded in twice
    suppress_output do
      load Rails.root.join('../../lib/bulk_dependency_eraser/nullifier.rb')
    end
  end

  context 'using DEFAULT_DB_WRAPPER' do
    it "should execute within a database writing role" do
      do_request

      expect(subject.errors).to be_empty

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :writing).exactly(2).times
    end
  end
end