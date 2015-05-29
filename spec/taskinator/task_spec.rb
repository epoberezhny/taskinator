require 'spec_helper'

describe Taskinator::Task do

  let(:definition) do
    Module.new do
      extend Taskinator::Definition
    end
  end

  describe "Base" do

    let(:process) { Class.new(Taskinator::Process).new(definition) }
    subject { Class.new(Taskinator::Task).new(process) }

    describe "#initialize" do
      it { expect(subject.process).to_not be_nil }
      it { expect(subject.process).to eq(process) }
      it { expect(subject.uuid).to_not be_nil }
      it { expect(subject.options).to_not be_nil }
    end

    describe "#<==>" do
      it { expect(subject).to be_a(::Comparable)  }
      it {
        uuid = subject.uuid
        expect(subject == double('test', :uuid => uuid)).to be
      }

      it {
        expect(subject == double('test', :uuid => 'xxx')).to_not be
      }
    end

    describe "#to_s" do
      it { expect(subject.to_s).to match(/#{subject.uuid}/) }
    end

    describe "#queue" do
      it {
        expect(subject.queue).to be_nil
      }

      it {
        task = Class.new(Taskinator::Task).new(process, :queue => :foo)
        expect(task.queue).to eq(:foo)
      }
    end

    describe "#current_state" do
      it { expect(subject).to be_a(::Workflow)  }
      it { expect(subject.current_state).to_not be_nil }
      it { expect(subject.current_state.name).to eq(:initial) }
    end

    describe "#can_complete_task?" do
      it {
        expect {
          subject.can_complete_task?
        }.to raise_error(NotImplementedError)
      }
    end

    describe "workflow" do
      describe "#enqueue!" do
        it { expect(subject).to respond_to(:enqueue!) }
        it {
          expect(subject).to receive(:enqueue)
          subject.enqueue!
        }
        it {
          subject.enqueue!
          expect(subject.current_state.name).to eq(:enqueued)
        }
        it {
          expect {
            subject.enqueue!
          }.to change { Taskinator.queue.tasks.length }.by(1)
        }
      end

      describe "#start!" do
        it { expect(subject).to respond_to(:start!) }
        it {
          expect(subject).to receive(:start)
          subject.start!
        }
        it {
          subject.start!
          expect(subject.current_state.name).to eq(:processing)
        }
      end

      describe "#complete!" do
        it { expect(subject).to respond_to(:complete!) }
        it {
          expect(subject).to receive(:can_complete_task?) { true }
          expect(subject).to receive(:complete)
          expect(process).to receive(:task_completed).with(subject)
          subject.start!
          subject.complete!
          expect(subject.current_state.name).to eq(:completed)
        }
      end

      describe "#fail!" do
        it { expect(subject).to respond_to(:fail!) }
        it {
          error = StandardError.new
          expect(subject).to receive(:fail).with(error)
          expect(process).to receive(:task_failed).with(subject, error)
          subject.start!
          subject.fail!(error)
        }
        it {
          subject.start!
          subject.fail!
          expect(subject.current_state.name).to eq(:failed)
        }
      end

      describe "#paused?" do
        it { expect(subject.paused?).to_not be }
        it {
          process.start!
          process.pause!
          expect(subject.paused?).to be
        }
      end

      describe "#cancelled?" do
        it { expect(subject.cancelled?).to_not be }
        it {
          process.cancel!
          expect(subject.cancelled?).to be
        }
      end
    end

    describe "#next" do
      it { expect(subject).to respond_to(:next) }
      it { expect(subject).to respond_to(:next=) }
    end

    describe "#accept" do
      it { expect(subject).to be_a(Taskinator::Persistence) }

      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)

        subject.accept(visitor)
      }
    end

    describe "#reload" do
      it { expect(subject.reload).to_not be }
    end
  end

  describe Taskinator::Task::Step do
    it_should_behave_like "a task", Taskinator::Task::Step do
      let(:process) { Class.new(Taskinator::Process).new(definition) }
      let(:task) { Taskinator::Task.define_step_task(process, :method, {:a => 1, :b => 2}) }
    end

    let(:process) { Class.new(Taskinator::Process).new(definition) }
    subject { Taskinator::Task.define_step_task(process, :method, {:a => 1, :b => 2}) }

    describe "#executor" do
      it { expect(subject.executor).to_not be_nil }
      it { expect(subject.executor).to be_a(definition) }
    end

    describe "#start!" do
      it "invokes executor" do
        expect(subject.executor).to receive(subject.method).with(*subject.args)
        subject.start!
      end

      it "handles failure" do
        error = StandardError.new
        allow(subject.executor).to receive(subject.method).with(*subject.args).and_raise(error)
        expect(subject).to receive(:fail!).with(error)
        subject.start!
      end
    end

    describe "#can_complete_task?" do
      it { expect(subject.can_complete_task?).to_not be }
      it {
        allow(subject.executor).to receive(subject.method).with(*subject.args)
        subject.start!
        expect(subject.can_complete_task?).to be
      }
    end

    describe "#accept" do
      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_attribute).with(:method)
        expect(visitor).to receive(:visit_args).with(:args)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Task::Job do

    module TestJob
      def self.perform(*args)
      end
    end

    it_should_behave_like "a task", Taskinator::Task::Job do
      let(:process) { Class.new(Taskinator::Process).new(definition) }
      let(:task) { Taskinator::Task.define_job_task(process, TestJob, {:a => 1, :b => 2}) }
    end

    let(:process) { Class.new(Taskinator::Process).new(definition) }
    subject { Taskinator::Task.define_job_task(process, TestJob, {:a => 1, :b => 2}) }

    describe "#enqueue!" do
      it {
        expect {
          subject.enqueue!
        }.to change { Taskinator.queue.jobs.length }.by(1)
      }
    end

    describe "#perform" do
      it {
        block = SpecSupport::Block.new
        expect(block).to receive(:call).with(TestJob, {:a => 1, :b => 2})

        subject.perform &block
      }
    end

    describe "#accept" do
      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_type).with(:job)
        expect(visitor).to receive(:visit_args).with(:args)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Task::SubProcess do
    it_should_behave_like "a task", Taskinator::Task::SubProcess do
      let(:process) { Class.new(Taskinator::Process).new(definition) }
      let(:sub_process) { Class.new(Taskinator::Process).new(definition) }
      let(:task) { Taskinator::Task.define_sub_process_task(process, sub_process) }
    end

    let(:process) { Class.new(Taskinator::Process).new(definition) }
    let(:sub_process) { Class.new(Taskinator::Process).new(definition) }
    subject { Taskinator::Task.define_sub_process_task(process, sub_process) }

    describe "#start!" do
      it "delegates to sub process" do
        expect(sub_process).to receive(:start)
        subject.start!
      end

      it "handles failure" do
        error = StandardError.new
        allow(sub_process).to receive(:start!).and_raise(error)
        expect(subject).to receive(:fail!).with(error)
        subject.start!
      end
    end

    describe "#can_complete_task?" do
      it "delegates to sub process" do
        expect(sub_process).to receive(:completed?)
        subject.can_complete_task?
      end
    end

    describe "#accept" do
      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_process).with(:sub_process)

        subject.accept(visitor)
      }
    end
  end

end
