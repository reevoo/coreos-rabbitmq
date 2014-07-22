# RabbitMQ
#
# VERSION    0.0.1

FROM ubuntu:14.04

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y -q install wget software-properties-common curl
RUN apt-add-repository ppa:brightbox/ruby-ng
RUN apt-get update
RUN apt-get install ruby2.1 -y -q
RUN echo 'gem: --no-document' >> ~/.gemrc

RUN wget http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
RUN apt-key add rabbitmq-signing-key-public.asc
RUN echo "deb http://www.rabbitmq.com/debian/ testing main" > /etc/apt/sources.list.d/rabbitmq.list
RUN apt-get update
RUN apt-get -y -q install rabbitmq-server
RUN /usr/sbin/rabbitmq-plugins enable rabbitmq_management
RUN echo "[{rabbit, [{loopback_users, []}]}]." > /etc/rabbitmq/rabbitmq.config
ENV RABBITMQ_SERVER_START_ARGS -eval error_logger:tty(true).

RUN gem install rabbitmq-cluster -v 0.0.19

#THIS IS A HACK TO TEST SHIT ON VAGRANT WITHOUT DNS
RUN mkdir -p /override_lib && cp /etc/hosts /var/ && cp /lib/x86_64-linux-gnu/libnss_files.so.2 /override_lib
RUN sed -ie 's:/etc/hosts:/var/hosts:g' /override_lib/libnss_files.so.2
ENV LD_LIBRARY_PATH /override_lib
RUN echo "172.17.8.101 core-01" >> /var/hosts
RUN echo "172.17.8.102 core-02" >> /var/hosts
RUN echo "172.17.8.103 core-03" >> /var/hosts

EXPOSE 4369 5672 15672 25672
ENTRYPOINT /usr/local/bin/rabbitmq-cluster & /usr/local/bin/rabbitmq-cluster-prestart && /usr/sbin/rabbitmq-server
