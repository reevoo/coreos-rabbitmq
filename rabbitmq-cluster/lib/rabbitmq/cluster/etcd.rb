require 'etcd'

class RabbitMQ::Cluster
  class Etcd
    attr_accessor :client
    private :client

    def self.build
      puts "etcd address: #{ENV['ETCD_HOST']}"
      new(
        ::Etcd::Client.new(host: ENV['ETCD_HOST'])
      )
    end

    def initialize(client)
      self.client = client
    end

    def acquire_lock
      client.compare_and_swap('/rabbitmq/lock', value: true, prevValue: false)
      yield
    rescue ::Etcd::TestFailed
      client.watch('/rabbitmq/lock')
      retry
    ensure
      client.set('/rabbitmq/lock', value: false)
    end

    def nodes
      with_retry do
        begin
          client.get('/rabbitmq/nodes').children.map(&:value).sort
        rescue ::Etcd::KeyNotFound
          []
        end
      end
    end

    def register(node_name, wait=nil)
      with_retry(wait) do
        client.set(key_for(node_name), value: node_name, ttl: 10)
      end
    end

    def erlang_cookie
      with_retry do
        client.get('/rabbitmq/erlang_cookie').value
      end
    end

    def erlang_cookie=(erlang_cookie)
      with_retry do
        client.set(
          '/rabbitmq/erlang_cookie',
          value: erlang_cookie
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
