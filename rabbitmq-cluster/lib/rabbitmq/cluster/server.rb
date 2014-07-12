require 'rabbitmq_manager'
require "rabbitmq/cluster/etcd"

class RabbitMQManager
  def aliveness_test(vhost)
    @conn.get(url :'aliveness-test', vhost).body
  end
end

class RabbitMQ::Cluster
  class Server
    attr_accessor :client, :etcd
    private :client, :etcd

    def self.build
      new(
        ::RabbitMQManager.new(ENV['RABBITMQ_MNGR'] || 'http://guest:guest@localhost:15672'),
        ::RabbitMQ::Cluster::Etcd.build
      )
    end

    def initialize(client, etcd)
      self.client = client
      self.etcd = etcd
    end

    def prestart
      setup_erlang_cookie
    end

    def synchronize
      join_cluster
      remove_stopped_nodes if stopped_nodes.any?
    end

    def healthcheck
      register if up?
    end

    def name
      @_name ||= client.overview["node"]
    end

    def up?
      client.aliveness_test('/')['status'] == 'ok'
    rescue Faraday::ConnectionFailed
      false
    end

    private

    def register
      etcd.register(name)
    end

    def running_nodes
      nodes(true)
    end

    def stopped_nodes
      nodes(false)
    end

    def remove_stopped_nodes
      etcd.aquire_lock do
        stopped_nodes.each do |node_name|
          system("rabbitmqctl forget_cluster_node #{node_name}")
        end
      end
    end

    def nodes(running)
      client.nodes.select { |n| n["running"] == running }.map { |n| n["name"] }.sort
    end

    def join_cluster
      if !clustered? && nodes_to_join.any? && up?
        system("rabbitmqctl stop_app")
        system("rabbitmqctl join_cluster #{nodes_to_join.first}")
        system("rabbitmqctl start_app")
        sleep 1 until up?
        register
      end
    end

    def clustered?
      client.nodes.size > 1
    rescue Faraday::ConnectionFailed
      false
    end

    def nodes_to_join
      etcd.nodes - [name]
    end

    def setup_erlang_cookie
      fail "erlang cookie must be preset in etcd" unless etcd.erlang_cookie
      File.open('/var/lib/rabbitmq/.erlang.cookie', 'w') { |file| file.write etcd.erlang_cookie }
      `chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie`
      `chmod 400 /var/lib/rabbitmq/.erlang.cookie`
    end
  end
end
