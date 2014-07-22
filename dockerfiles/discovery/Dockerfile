# RabbitMQ
#
# VERSION    0.0.1

FROM errm/little-ruby-docker:2.1.2

RUN echo 'gem: --no-rdoc' >> ~/.gemrc
RUN echo 'gem: --no-ri' >> ~/.gemrc
RUN gem install rabbitmq-cluster -v 0.0.19
RUN adduser -H -D conan
USER conan

ENTRYPOINT ["/usr/bin/rabbitmq-cluster-discovery"]
