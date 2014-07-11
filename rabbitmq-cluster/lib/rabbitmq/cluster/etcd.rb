require 'etcd'

module RabbitMQ::Cluster
  class Etcd
    attr_accessor :client
    private :client

    def initialize(client)
      self.client = client
      client.connect
    end

    def aquire_lock
      sleep 1 until lock = client.update('/rabbitmq/lock', true, false)
      yield if lock
    ensure
      client.update('/rabbitmq/lock', false, true)
    end

    def nodes
      (client.get('/rabbitmq/nodes') || {}).values.sort
    end

    def register(node_name)
      client.set(key_for(node_name), node_name, ttl: 10)
      try = 0
    rescue
      sleep 1
      try += 1
      retry if try < 10
    end

    def erlang_cookie
      client.get('/rabbitmq/erlang_cookie')
    end

    def erlang_cookie=(erlang_cookie)
      client.set(
        '/rabbitmq/erlang_cookie',
        erlang_cookie
      )
    end

    private

    def key_for(node_name)
      "/rabbitmq/nodes/#{node_name}"
    end
  end
end
