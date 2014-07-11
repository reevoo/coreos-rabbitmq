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
      return if etcd.nodes.size == running_nodes.size

      etcd.aquire_lock do
        stopped_nodes.each do |node|
          `rabbitmqctl forget_cluster_node #{node['name']}`
          etcd.deregister(node['name'])
        end
      end
    end

    def name
      @_name ||= client.overview["cluster_name"]
    end

    def up?
      test_aliveness?
    rescue Faraday::ConnectionFailed
      false
    end

    private

    def running_nodes
      client.nodes.select { |n| n["running"] }
    end

    def stopped_nodes
      client.nodes.select { |n| !n["running"] }
    end

    def test_aliveness?
      unless client.vhosts.any? {|vh| vh['name'] == 'aliveness-test' }
        client.vhost_create('aliveness-test')
      end

      unless client.user_permissions('guest').any? {|up| up['vhost'] == 'aliveness-test' }
        client.user_set_permissions('guest', 'aliveness-test', '.*', '.*', '.*')
      end

      client.aliveness_test('aliveness-test')['status'] == 'ok'
    end

    def join_cluster
      if !clustered? && nodes_to_join.any?
        `rabbitmqctl stop_app`
        system("rabbitmqctl join_cluster #{nodes_to_join.first}")
        `rabbitmqctl start_app`
      end
      etcd.register(name)
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
