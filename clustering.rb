require 'rabbitmq_manager'
require 'etcd'

def setup_cluster
  if clustered?
    ensure_registered(nodename)
  else
    if reigstered_nodes.any?
      join_cluster
    end
  end
end

def join_cluster
  `rabbitmqctl stop_app`
  raise unless system("rabbitmqctl join_cluster #{registered_nodes.last}")
  `rabbitmqctl start_app`
  ensure_registered(nodename)
end

def reigstered_nodes
  etcd.get('/rabbitmq/nodes').keys
end

def clustered?
  rabbitmq.nodes.size > 1
end

def ensure_registered(nodename)
  key = "/rabbitmq/nodes/#{nodename}"
  unless etcd.exists?(key)
    etcd.set(key, true)
  end
end

def rabbitmq
  RabbitMQManager.new 'http://guest:guest@localhost:15672'
end

def etcd
  unless @client
    @client = Etcd::Client.connect(uris: 'http://localhost:4001')
    @client.connect
  end
  @client
end

setup_cluster
