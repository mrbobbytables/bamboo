################################################################################
# bamboo:1.2.0
# Date: 1/22/2016
# Bamboo Version: v0.2.15
# HAproxy Version: 1.6.3-1ppa1~trusty
# Keepalived Version: 1:1.2.7-1ubuntu1
#
# Description:
# Bamboo container for use with Marathon, packaged with haproxy and 
# keepalived for additional high availability.
################################################################################

FROM mrbobbytables/ubuntu-base:1.1.0
MAINTAINER Bob Killen / killen.bob@gmail.com / @mrbobbytables


ENV VERSION_BAMBOO=v0.2.15               \
    VERSION_HAPROXY=1.6.3-1ppa1~trusty   \
    VERSION_KEEPALIVED=1:1.2.7-1ubuntu1

RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1C61B9CD                                                         \
 && echo "deb http://ppa.launchpad.net/vbernat/haproxy-1.6/ubuntu trusty main" >> /etc/apt/sources.list.d/haproxy.list        \
 && echo "deb-src http://ppa.launchpad.net/vbernat/haproxy-1.6/ubuntu trusty main" >> /etc/apt/sources.list.d/haproxy.list    \
 && export GOROOT=/opt/go           \
 && export GOPATH=/opt/go/gopkg     \
 && export PATH=$PATH:/opt/go/bin   \
 && export USER=root                \
 && apt-get update                  \
 && apt-get -y install              \
    haproxy=$VERSION_HAPROXY        \
    git                             \
    iptables                        \
    keepalived=$VERSION_KEEPALIVED  \
    make                            \
    ruby                            \
    ruby-dev                        \
    wget                            \
 && gem install fpm                 \
 && wget -P /tmp https://storage.googleapis.com/golang/go1.4.2.linux-amd64.tar.gz    \
 && tar -xvzf /tmp/go1.4.2.linux-amd64.tar.gz -C /opt/                               \
 && go get github.com/QubitProducts/bamboo                                           \
 && cd $GOPATH/src/github.com/QubitProducts/bamboo                                   \
 && git checkout $VERSION_BAMBOO                                                     \
 && go build bamboo.go                                                               \
 && ./builder/build.sh                                                               \         
 && dpkg -i $GOPATH/src/github.com/QubitProducts/bamboo/output/bamboo*.deb           \
 && gem list --no-version | xargs gem uninstall -ax                                  \
 && apt-get purge -y                     \
     wget                                \
     make                                \
     ruby                                \
     ruby-dev                            \
     git                                 \
 && apt-get -y clean                     \
 && apt-get -y autoremove                \
 && rm -r /var/lib/gems                  \
 && rm -r /opt/go                        \
 && rm -r /tmp/*

COPY ./skel /

RUN chmod +x init.sh              \
 && chmod 640 /etc/logrotate.d/*  \
 && touch /var/run/haproxy.stat   \
 && mkdir -p /var/log/bamboo      \ 
 && chown -R logstash-forwarder:logstash-forwarder /opt/logstash-forwarder


CMD ["./init.sh"]
