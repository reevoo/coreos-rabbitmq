require 'spec_helper'

describe RabbitMQ::Cluster::Server do
  let(:client) { double }
  let(:etcd) { FakeEtcd.new }

  subject { described_class.new(client, etcd) }

  describe '.build' do
    before do
      allow(RabbitMQ::Cluster::Etcd).to receive(:build).and_return(etcd)
      allow(RabbitMQManager).to receive(:new).and_return(client)
    end

    it 'sets up an instance' do
      expect(described_class).to receive(:new).with(client, etcd)
      described_class.build
    end
  end

  describe '#name' do
    let(:client) do
      double(
        :rmq,
        overview: { 'node' => 'rabbit@awesome-node' }
      )
    end

    it 'gets the name from RabbitMQ' do
      expect(subject.name).to eq 'rabbit@awesome-node'
    end

    it 'is cached so we can still access the name when the rabbitmq management api is down' do
      subject.name
      allow(client).to receive(:overview).and_raise
      expect(subject.name).to eq 'rabbit@awesome-node'
    end
  end

  describe 'up?' do
    let(:client) { double(:client).as_null_object }

    before do
      allow(client).to receive(:aliveness_test).and_return({ "status" => "ok" })
    end

    it 'returns false if we cannot connect to the management api' do
      allow(client).to receive(:aliveness_test).and_raise(Faraday::ConnectionFailed, "error")
      expect(subject).to_not be_up
    end

    context 'we can can connect to the management api' do
      context 'the aliveness test is working' do
        specify { expect(subject).to be_up }
      end

      context 'the aliveness test is not working' do
        before do
          allow(client).to receive(:aliveness_test).and_return({ "status" => "borked" })
        end

        specify { expect(subject).to_not be_up }
      end
    end
  end


  describe '#prestart' do
    context 'with an erlang cookie in etcd' do
      before do
        allow(File).to receive(:open)
        allow(subject).to receive(:"`")
        allow(etcd).to receive(:erlang_cookie).and_return('NummmNugnnmNuyum')
      end

      it 'sets up the erlang cookie' do
        expect(File).to receive(:open).with('/var/lib/rabbitmq/.erlang.cookie', 'w')
        subject.prestart
      end

      it 'sets up the ownership and permissions of the erlang cooke' do
        expect(subject).to receive(:"`")
          .with("chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie")
        expect(subject).to receive(:"`")
          .with("chmod 400 /var/lib/rabbitmq/.erlang.cookie")
        subject.prestart
      end
    end

    context 'when there was no erlang cookie in etcd' do
      before do
        allow(etcd).to receive(:erlang_cookie).and_return(false)
      end

      it 'fails hard and fast' do
        expect { subject.prestart }.to raise_error('erlang cookie must be preset in etcd')
      end
    end
  end

  describe '#synchronize' do
    before do
      allow(client).to receive(:nodes)
      .and_return([
                  {"name" => "rabbit@node1", "running" => true},
                  {"name" => "rabbit@node2", "running" => false}
      ])
      allow(subject).to receive(:system)
      allow(client).to receive(:aliveness_test).and_return("status" => "ok")
      allow(client).to receive(:overview).and_return("node" => "rabbit@this_node")
    end

    context 'the node is not up' do
      before do
        allow(client).to receive(:aliveness_test).and_return("status" => "agghghghgh")
      end

      it 'does not register the node' do
        expect(etcd).to_not receive(:register).with('rabbit@this_node')
        subject.synchronize
      end
    end

    context 'the node is up' do
      it 'removes the stopped node from the cluster' do
        expect(subject).to receive(:system)
        .with('rabbitmqctl forget_cluster_node rabbit@node2')
        subject.synchronize
      end
    end

    describe 'joining the cluster' do
      let(:client) { double(:client).as_null_object }

      before do
        allow(subject).to receive(:system)
        allow(subject).to receive(:"`")
        allow(client).to receive(:aliveness_test).and_return({ "status" => "ok" })
      end


      context 'with no nodes in etcd' do
        it 'does nothing' do
          expect(subject).to_not receive(:"`")
          subject.synchronize
        end
      end

      context 'with some nodes allready in etcd' do
        before do
          allow(client).to receive(:nodes)
          .and_return([{}])
          etcd.register('rabbit@node1')
          etcd.register('rabbit@node2')
        end

        context 'allready in a cluster' do
          before do
            allow(client).to receive(:nodes)
            .and_return([{},{}])
          end

          it 'does nothing' do
            expect(subject).to_not receive(:system)
            subject.synchronize
          end
        end

        it 'tries to join the cluster' do
          expect(subject).to receive(:system).with("rabbitmqctl join_cluster rabbit@node1")
          subject.synchronize
        end

        it 'stops the management app before clustering' do
          expect(subject).to receive(:system)
            .with('rabbitmqctl stop_app')
          expect(subject).to receive(:system)
            .with('rabbitmqctl start_app')
          subject.synchronize
        end

        it 'does not try to cluster with itself' do
          allow(client).to receive(:overview).and_return('node' => 'rabbit@node1')
          expect(subject).to receive(:system).with("rabbitmqctl join_cluster rabbit@node2")
          subject.synchronize
        end

        it 'registers itself' do
          allow(client).to receive(:overview).and_return('node' => 'rabbit@this_node')
          subject.synchronize
          expect(etcd.nodes).to include('rabbit@this_node')
        end
      end
    end
  end

  describe '#healthcheck' do
    context 'the node is up' do
      before do
        allow(client).to receive(:aliveness_test).and_return("status" => "ok")
        allow(client).to receive(:overview).and_return("node" => "rabbit@this_node")
      end

      it 'registers the node' do
        expect(etcd).to receive(:register).with('rabbit@this_node')
        subject.healthcheck
      end
    end

    context 'the node is down' do
      before do
        allow(client).to receive(:aliveness_test).and_return("status" => "i am really broken")
      end

      it 'registers the node' do
        expect(etcd).to_not receive(:register)
        subject.healthcheck
      end
    end
  end

end

class FakeEtcd

  attr_accessor :erlang_cookie, :nodes

  def initialize
    self.nodes = []
  end

  def acquire_lock
    yield
  end

  def register(node)
    nodes << node
  end

end
