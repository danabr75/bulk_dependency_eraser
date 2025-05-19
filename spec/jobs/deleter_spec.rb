require 'rails_helper'

RSpec.describe BulkDependencyEraser::Deleter do
  fixtures('users')
  subject { described_class.new(class_names_and_ids:, additional_identifiers_by_id:, opts:) }
  let(:opts) { {} }
  let(:class_names_and_ids) { {} }
  let(:additional_identifiers_by_id) { {} }
  let(:do_request) { subject.execute }

  context "when deleting by partition and CTID PG system column" do
    let(:opts) do
      { use_pg_system_column_ctid: true, use_ctid_over_primary_key: true, delete_ctids_by_partions: true }
    end
    let(:model_klass) { User }
    let!(:user) { model_klass.find_by_email('test@test.test') }
    let(:class_names_and_ids) do
      {
        User.name => [
          user.id
        ]
      }
    end
    let(:additional_identifiers_by_id) do
      {
        user.id => {
          'ctid' => user.ctid,
          'tableoid' => user.tableoid,
        }
      }
    end


    it "should execute successfully" do
      aggregate_failures do
        expect(do_request).to be_truthy
        expect(subject.errors).to be_empty
      end
    end

    it "should only delete one user" do
      expected_ids = User.pluck(:id) - [user.id]
      do_request
      expect(User.pluck(:id)).to match(expected_ids)
    end
  end
end
