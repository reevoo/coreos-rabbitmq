require 'spec_helper'

describe RabbitMQ::Cluster::Etcd do
  let(:etcd_client) { double(:etcd) }
  subject { described_class.new(etcd_client) }

  describe '.build' do
    before do
      allow(Etcd::Client).to receive(:new).and_return(etcd_client)
    end

    it 'sets up an instance' do
      expect(described_class).to receive(:new).with(etcd_client)
      described_class.build
    end
  end

  describe '#nodes' do
    it 'returns the list of nodes registed in etcd' do
      allow(etcd_client).to receive(:get).with('/rabbitmq/nodes').and_return(
        double(:response,
               children: [
                 double(:response, value: "rabbit@rabbit1"),
                 double(:response, value: "rabbit@rabbit2")
               ]
              )
      )
      expect(subject.nodes).to eq ["rabbit@rabbit1", "rabbit@rabbit2"]
    end

    it 'returns an empty array if there are no nodes registered' do
      allow(etcd_client).to receive(:get).with('/rabbitmq/nodes').and_return(
        double(:response, children: [])
      )
      expect(subject.nodes).to eq []
    end

    it 'returns an empty array if the nodes directory has not been created' do
      allow(etcd_client).to receive(:get).with('/rabbitmq/nodes').and_raise(Etcd::KeyNotFound)
      expect(subject.nodes).to eq []
    end
  end

  describe '#register' do
    let(:nodename) { 'rabbit@mynode' }

    it 'sets the key in etcd' do
      expect(etcd_client).to receive(:set)
      .with(
        "/rabbitmq/nodes/#{nodename}",
        value: nodename,
        ttl: 10
      )
      subject.register(nodename)
    end

    context 'somthing is wrong with etcd backend' do
      before do
        allow(subject).to receive(:wait).and_return(0.001)
      end

      it 'retry 10 times' do
        expect(etcd_client).to receive(:set).exactly(10).times.and_raise
        expect { subject.register('foo', 0.0001) }.to raise_error
      end
    end
  end


  describe '#erlang_cookie' do
    let(:erlang_cookie) { 'afbdgCVB23423bh324h' }
    before do
      allow(etcd_client).to receive(:get)
                              .with('/rabbitmq/erlang_cookie')
                              .and_return(double(:response, value: erlang_cookie))
    end

    it 'has a getter' do
      expect(subject.erlang_cookie).to eq erlang_cookie
    end

    it 'has a setter' do
      expect(etcd_client).to receive(:set)
                               .with(
                                 '/rabbitmq/erlang_cookie',
                                 value: erlang_cookie
                               )
      subject.erlang_cookie = erlang_cookie
    end
  end

  describe '#acquire_lock' do
    before do
      allow(etcd_client).to receive(:compare_and_swap).with('/rabbitmq/lock', value: true, prevValue: false)
      allow(etcd_client).to receive(:set).with('/rabbitmq/lock', value: false)
    end

    describe 'when we can get the lock' do
      it 'runs the code' do
        expect(etcd_client).to receive(:compare_and_swap).with('/rabbitmq/lock', value: true, prevValue: false)
        expect { |b| subject.acquire_lock(&b) }.to yield_control
      end

      it 'gives the lock back when its done' do
        expect(etcd_client).to receive(:set).with('/rabbitmq/lock', value: false)
        expect { |b| subject.acquire_lock(&b) }.to yield_control
      end
    end

    describe "when we can't get the lock" do
      it 'retries till the lock can be acquired' do
        allow(etcd_client).to receive(:watch)
        call_count = 0
        expect(etcd_client).to receive(:compare_and_swap).with('/rabbitmq/lock', value: true, prevValue: false) do
          call_count += 1
          raise Etcd::TestFailed unless call_count == 3
        end
        expect { |b| subject.acquire_lock(&b) }.to yield_control
      end
    end

    describe 'when something explodes' do
      before do
        allow(etcd_client).to receive(:compare_and_swap)
      end

      it 'gives the lock back' do
        expect(etcd_client).to receive(:set).with('/rabbitmq/lock', value: false)
        expect { subject.acquire_lock { fail } }.to raise_error
      end
    end
  end
end
