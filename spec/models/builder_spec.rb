require 'rails_helper'

RSpec.describe BulkDependencyEraser::Builder do
  fixtures(ALL_FIXTURE_TABLES.call)

  let(:model_klass) { User }
  let(:query) { model_klass }
  let(:params) { { query: model_klass } }
  subject { described_class.new(**params) }
  let(:do_request) { subject.execute }


  before do
    allow(ActiveRecord::Base).to receive(:connected_to).and_yield

    # We have to recall the class, so that it'll have the stubbed ActiveRecord::Base in it's DEFAULT_DB_WRAPPER proc.
    # - if we didn't, we'd have no way to confirm that ActiveRecord::Base had it's :connected_to method called
    # - suppressing warnings about redefining constants, from the class being loaded in twice
    suppress_output do
      load Rails.root.join('../../lib/bulk_dependency_eraser/builder.rb')
    end
  end

  context 'using DEFAULT_DB_WRAPPER' do
    it "should execute within a database reading role" do
      do_request

      expect(subject.nullification_list).to be_empty
      expect(subject.deletion_list).not_to be_empty
      expect(subject.errors).to be_empty

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :reading).exactly(29).times
    end
  end

  context 'using custom batch_size' do
    let(:params) { super().merge(opts: { batch_size: 1 }) }

    it "should execute within a database reading role" do
      do_request

      expect(subject.nullification_list).to be_empty
      expect(subject.deletion_list).not_to be_empty
      expect(subject.errors).to be_empty

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :reading).exactly(29).times
    end
  end

  context 'when build query error occurs' do
    before do
      allow_any_instance_of(ActiveRecord::Relation).to receive(:pluck).and_raise(StandardError.new("Pluck is forbidden"))
    end

    it "should catch and report the BuilderError" do
      do_request

      expect(subject.errors).to eq(["Issue attempting to build deletion query for 'User' => StandardError: Pluck is forbidden"])
    end
  end
end