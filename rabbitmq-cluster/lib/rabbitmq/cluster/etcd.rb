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
      with_retry do
        sleep 1 until lock = client.update('/rabbitmq/lock', true, false)
      end
      yield
    ensure
      client.update('/rabbitmq/lock', false, true)
    end

    def nodes
      with_retry do
        (client.get('/rabbitmq/nodes') || {}).values.sort
      end
    end

    def register(node_name, wait=nil)
      with_retry(wait) do
        client.set(key_for(node_name), node_name, ttl: 10)
      end
    end

    def erlang_cookie
      with_retry do
        client.get('/rabbitmq/erlang_cookie')
      end
    end

    def erlang_cookie=(erlang_cookie)
      with_retry do
        client.set(
          '/rabbitmq/erlang_cookie',
          erlang_cookie
        )
      end
    end

    private

    def with_retry(wait = nil)
      wait ||= 1
      try = 0
      begin
        yield
      rescue
        sleep wait
        try += 1
        retry if try < 10
        raise
      end
    end

    def key_for(node_name)
      "/rabbitmq/nodes/#{node_name}"
    end
  end
end
