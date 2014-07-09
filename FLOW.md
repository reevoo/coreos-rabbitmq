Prestart Config
  (get or set erlang cookie from etcd

Starts RabbitMQ

Poststart Config 
  (enforce ha mode)

Reads /rabbitmq/nodes/*
Joins cluster

Set /rabbitmq/nodes/mynodename

Watches /rabbitmq/nodes/*
   wait for new nodes to join
   Checks real cluster status
     If I am not clustered with other nodes try to join them
