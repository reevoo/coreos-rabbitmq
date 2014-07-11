require 'spec_helper'

describe RabbitMQ::Cluster::Server do
  let(:client) { double }
  let(:etcd) { FakeEtcd.new }

  subject { described_class.new(client, etcd) }

  describe '#name' do
    let(:client) do
      double(
        :rmq,
        overview: { 'cluster_name' => 'rabbit@awesome-node' }
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
      context 'and the test vhost is allready setup' do
        before do
          allow(client).to receive(:vhosts).and_return([{'name' => 'aliveness-test'}])
          allow(client).to receive(:user_permissions).and_return([{'vhost' => 'aliveness-test'}])
        end

        it 'wont set up the vhost' do
          expect(client).to_not receive(:vhost_create)
          expect(client).to_not receive(:user_set_permissions)
          subject.up?
        end
      end

      context 'and the test vhost is not setup' do

        before do
          allow(client).to receive(:vhosts).and_return([])
          allow(client).to receive(:user_permissions).and_return([])
        end

        it 'will set up the vhost' do
          expect(client).to receive(:vhost_create).with('aliveness-test')
          expect(client).to receive(:user_set_permissions).with('guest', 'aliveness-test', '.*', '.*', '.*')
          subject.up?
        end
      end

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

  describe 'starting the server' do
    let(:client) { double(:client).as_null_object }

    before do
      allow(subject).to receive(:system)
      allow(client).to receive(:aliveness_test).and_return({ "status" => "ok" })
      allow(File).to receive(:open)
      allow(IO).to receive(:read)
      allow(subject).to receive(:"`")
    end

    it 'shells out to start rabbitmq-server' do
      expect(subject).to receive(:system).with("/usr/sbin/rabbitmq-server &")
      subject.start
    end

    context 'waiting for the server to start' do
      it 'waits until the server has started' do
        expect(subject).to receive(:up?).twice.and_return(false, true)
        subject.start
      end
    end

    describe 'joining the cluster' do
      context 'with no nodes in etcd' do
        it 'does nothing' do
          expect(subject).to_not receive(:"`")
          subject.start
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
            expect(subject).to_not receive(:"`")
            subject.start
          end

          it 'registers itself' do
            allow(client).to receive(:overview).and_return('cluster_name' => 'rabbit@this_node')
            subject.start
            expect(etcd.nodes).to include('rabbit@this_node')
          end
        end

        it 'tries to join the cluster' do
          expect(subject).to receive(:system).with("rabbitmqctl join_cluster rabbit@node1")
          subject.start
        end

        it 'stops the management app before clustering' do
          expect(subject).to receive(:"`")
                               .with('rabbitmqctl stop_app')
          expect(subject).to receive(:"`")
                               .with('rabbitmqctl start_app')
          subject.start
        end

        it 'does not try to cluster with itself' do
          allow(client).to receive(:overview).and_return('cluster_name' => 'rabbit@node1')
          expect(subject).to receive(:system).with("rabbitmqctl join_cluster rabbit@node2")
          subject.start
        end

        it 'registers itself' do
          allow(client).to receive(:overview).and_return('cluster_name' => 'rabbit@this_node')
          subject.start
          expect(etcd.nodes).to include('rabbit@this_node')
        end
      end
    end

    context 'with an erlang cookie in etcd' do

      before do
        allow(etcd).to receive(:erlang_cookie).and_return('NummmNugnnmNuyum')
      end

      it 'sets up the erlang cookie' do
        expect(File).to receive(:open).with('/var/lib/rabbitmq/.erlang.cookie', 'w')
        subject.start
      end

      it 'sets up the ownership and permissions of the erlang cooke' do
        expect(subject).to receive(:"`")
        .with("chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie")
        expect(subject).to receive(:"`")
        .with("chmod 400 /var/lib/rabbitmq/.erlang.cookie")
        subject.start
      end
    end

    context 'when there was no erlang cookie in etcd' do
      before do
        allow(IO).to receive(:read)
          .with('/var/lib/rabbitmq/.erlang.cookie')
          .and_return('ErLAnGCOookie')
      end

      it 'saves the on disk cookie to etcd' do
        subject.start
        expect(etcd.erlang_cookie).to eq 'ErLAnGCOookie'
      end
    end
  end

  describe '#synchronize' do
    context 'etcd has more nodes than are running' do
      before do
        etcd.register('rabbit@node1')
        etcd.register('rabbit@node2')
        allow(client).to receive(:nodes)
          .and_return([
            {"name" => "rabbit@node1", "running" => true},
            {"name" => "rabbit@node2", "running" => false}
          ])
        allow(subject).to receive(:"`")
        allow(etcd).to receive(:deregister)
      end

      it 'aquires the lock before doing anything' do
        expect(etcd).to receive(:aquire_lock).and_call_original
        subject.synchronize
      end

      it 'removes the stopped node from the cluster' do
        expect(subject).to receive(:"`")
          .with('rabbitmqctl forget_cluster_node rabbit@node2')
        subject.synchronize
      end

      it 'removes the stopped node from etcd' do
        expect(etcd).to receive(:deregister)
          .with('rabbit@node2')
        subject.synchronize
      end
    end

    context 'etcd has the same nodes as are running' do
      before do
        etcd.register('rabbit@node1')
        etcd.register('rabbit@node2')
        allow(client).to receive(:nodes)
          .and_return([
            {"name" => "rabbit@node1", "running" => true},
            {"name" => "rabbit@node2", "running" => true}
          ])
      end

      it 'does nothing' do
        expect(etcd).to_not receive(:aquire_lock)
        subject.synchronize
      end
    end
  end

end

class FakeEtcd

  attr_accessor :erlang_cookie, :nodes

  def initialize
    self.nodes = []
  end

  def aquire_lock
    yield
  end

  def register(node)
    nodes << node
  end

end
