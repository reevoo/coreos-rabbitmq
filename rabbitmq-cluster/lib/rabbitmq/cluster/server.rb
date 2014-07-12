require 'rabbitmq_manager'

class RabbitMQManager
  def aliveness_test(vhost)
    @conn.get(url :'aliveness-test', vhost).body
  end
end

module RabbitMQ::Cluster
  class Server
    attr_accessor :client, :etcd
    private :client, :etcd

    def self.build
      new(
        RabbitMQManager.new(ENV['RABBITMQ_MNGR'] || 'http://guest:guest@localhost:15672'),
        RabbitMQ::Cluster::Etcd.new(
          Etcd::Client.new(uri: ENV['ETCD_HOST'])
        )
      )
    end

    def initialize(client, etcd)
      self.client = client
      self.etcd = etcd
    end

    def start
      etcd.aquire_lock do
        setup_erlang_cookie
        start_rabbitmq_server
        save_erlang_cookie
        join_cluster
      end
    end

    def synchronize
      remove_stopped_nodes if stopped_nodes.any?
      join_cluster
    end

    def healthcheck
      register if up?
    end

    def name
      @_name ||= client.overview["cluster_name"]
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
        `rabbitmqctl stop_app`
        system("rabbitmqctl join_cluster #{nodes_to_join.first}")
        `rabbitmqctl start_app`
        register if up?
      end
    end

    def clustered?
      client.nodes.size > 1
    end

    def nodes_to_join
      etcd.nodes - [name]
    end

    def start_rabbitmq_server
      system("/usr/sbin/rabbitmq-server &")
      waits = 1
      until up?
        sleep waits
        waits *= 2
      end
    end

    def erlang_cookie
      IO.read('/var/lib/rabbitmq/.erlang.cookie')
    end

    def setup_erlang_cookie
      if etcd.erlang_cookie
        File.open('/var/lib/rabbitmq/.erlang.cookie', 'w') { |file| file.write etcd.erlang_cookie }
        `chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie`
        `chmod 400 /var/lib/rabbitmq/.erlang.cookie`
      end
    end

    def save_erlang_cookie
      unless etcd.erlang_cookie
        etcd.erlang_cookie = erlang_cookie
      end
    end

  end
end
