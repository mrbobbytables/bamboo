# - Bamboo - 
An Ubuntu based container built for the purpose of providing a highly available instance of HAproxy with integrated service-discovery and auto-configuration for Mesos Marathon.

Additional High availability is provided by Keepalived; a well-proven, battle-tested routing and failover service. The main reason for including Keepalived in addition to Mesos/Marathon's own HA is to keep downtime to an absolute minimum while maintaining a single set of forward facing IPs. This is useful for when DNS based load balancing may not be ideal.

##### Version Information:

* **Container Release:** 1.0.0
* **Bamboo:** v0.2.14
* **HAproxy:** 1.5.14-1ppa~trusty
* **Keepalived:** 1:1.2.7-1ubuntu1

##### Services Include
* **[Bamboo](#bamboo)** - A service-discovery and routing daemon that subscribes to Marathon events.
* **[HApoxy](#haproxy)** - The well known and high performance tcp/http load balancer.
* **[Rsyslog](#rsyslog)** - A system logging daemon. Bundled to support logging for HAproxy and Keepalived.
* **[Keepalived](#keepalived)** - A well known and frequently used framework that provides load-balancing and fault tolerance via VRRP (Virtual Router Redundancy Protocol).
* **[Logstash-Forwarder](#logstash-forwarder)** - A lightweight log collector and shipper for use with [Logstash](https://www.elastic.co/products/logstash).
* **[Redpill](#redpill)** - A bash script and healthcheck for supervisord managed services. It is capable of running cleanup scripts that should be executed upon container termination.



---
---
### Index
* [Usage](#usage)
 * [Before you Build or Run](#read-this-before-you-attempt-to-run-or-build)
 * [Example Run Command](#example-run-command)
 * [Example Marathon App Definition](#example-marathon-app-definition)
* [Modification and Anatomy of the Project](#modification-and-anatomy-of-the-project)
* [Important Environment Variables](#important-environment-variables)
* [Service Configuration](#service-configuration)
 * [Bamboo](#bamboo)
 * [HAproxy](#haproxy)
 * [Keepalived](#keepalived)
 * [Logstash-Forwarder](#logstash-forwarder)
 * [Redpill](#redpill)
* [Troubleshooting](#troubleshooting)

---
---

### Usage

#### READ THIS BEFORE YOU ATTEMPT TO RUN OR BUILD

There are three important components that should be configured before attempting to deploy this container:
 1. Configure Marathon.
 1. Configure the host.
 2. Modify the Haproxy template.

##### Marathon
Marathon must be configured with  the `http_callback` event subscriber enabled. To enable this, start marathon with the following environment variable setting:
* `MARATHON_EVENT_SUBSCRIBER="http_callback"`


##### Host Preparation
The host(s) that this is intended to run on must have a kernel setting configured for Keepalived to function correctly. If Keepalived is not going to be configured; this setting can be ignored.

* `net.ipv4.ip_nonlocal_bind=1` - For Keepalived to bind to an address that is not currently tied to a device.


##### Bamboo  HAproxy Template
While the Bamboo container can be used without modifying the HAproxy configuartion for testing purposes; in a production environment the HAProxy template should be tailored to your applications. The path to the template can either be specified in the Bamboo config (`/opt/bamboo/config/production.json`) or overriden with environment variable `HAPROXY_TEMPLATE_PATH`.

Bamboo uses Go's own text templating package with their own verbage. The example [haproxy template](https://github.com/QubitProducts/bamboo/blob/master/config/haproxy_template.cfg) in their [github repo](https://github.com/QubitProducts/bamboo) serves as a good reference. For further HAproxy configuration information, please see the [HAproxy Configuration Manual](https://cbonte.github.io/haproxy-dconv/index.html).


---

##### Deploying in Production

For a production deployment with Keepalived enabled; there are close to 20 environment variables that should be set. However, if a Bamboo configuration file is supplied, the Bamboo specific environment settings can be ignored **EXCEPT** `HAPROXY_OUTPUT_PATH`. This **MUST** be specified if using something other than default; as it is required for HAproxy to start correctly.

In addition to modifying the haproxy template, the only other important note is in reference to the reload command used to update the HAproxy's config. With HAproxy being managed by supervisord, and not running as a native service - it is best to be reloaded using `supervisorctl`. Below is an example reload command:

`iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done`

The above command will drop the `SYN` packet before the HAproxy process restarts forcing the clients to resend it to the new process. This will increase latency when HAproxy is reloaded; however it will not drop any packets. For more information on this technique and several others, [Yelp's Engineering Blog](http://engineeringblog.yelp.com/) has a useful [article](http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html) on the subject.

If using Keepalived or iptables for the reload command, both require host networking and the `NET_ADMIN` capability should be used for the container to work correctly.

**Configuration Parameters**

* `ENVIRONMENT` - Sets defaults for several other variables based on the current running environment. Please see the [environment](#environment) section for further information. If logstash-forwarder is enabled, this value will populate the `environment` field in the logstash-forwarder configuration file.

* `BAMBOO_BIND_ADDRESS` - The IP in which Bamboo will bind to.

* `BAMBOO_CONF` - The path to the Bamboo json config file.

* `HAPROXY_OUTPUT_PATH` - The path to the HAproxy config file (**required** even if specified in the configuration file).

* `KEEPALIVED_INTERFACE` - The host interface that keepalived will monitor and use for VRRP traffic. e.g. `eth0`

* `KEEPALIVED_VRRP_UNICAST_BIND` - The IP on the host that the keepalived daemon should bind to. **Note:** If not specified, it will be the first IP bound to the interface specified in `$KEEPALIVED_INTERFACE`

* `KEEPALIVED_VRRP_UNICAST_PEER` - The host IP of the peer in the VRRP group (the other host acting as an edge or proxy system).

* `KEEPALIVED_TRACK_INTERFACE_###` - An interface that’s state should be monitored (e.g. `eth0`). More than one can be supplied as long as the variable name ends in a number from 0-999.

* `KEEPALIVED_VIRTUAL_IPADDRESS_###` - An instance of an address that will be monitored and failed over from one host to another. These should be a quoted string in the form of: `<IPADDRESS>/<MASK> brd <BROADCAST_IP> dev <DEVICE> scope <SCOPE> label <LABEL>` At a minimum the ip address, mask and device should be specified e.g. `KEEPALIVED_VIRTUAL_IPADDRESS_1="10.10.0.2/24 dev eth0"`. More than one can be supplied as long as the variable name ends in a number from 0-999. Note: Keepalived has a hard limit of 20 addresses that can be monitored. More can be failed over with the monitored addresses via `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_###`. In general, this would be a floating IP on the private network side, and does not have to have any true intended purpose other than being a monitored IP.

* `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_###` - An instance of an address that will be failed over with the monitored addresses supplied via KEEPALIVED_VIRTUAL_IPADDRESS_###. These should be a quoted string in the form of: `<IPADDRESS>/<MASK> brd <BROADCAST_IP> dev <DEVICE> scope <SCOPE> label <LABEL>` At a minimum the ip address, mask and device should be specified e.g. `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1="172.16.1.20/24 dev eth1"`. More than one can be supplied as long as the variable name ends in a number from 0-999. This is ideal for any public facing IP addresses.


If the Bamboo config is to be supplied via environment variables, the below options should be supplied:

* `BAMBOO_ENDPOINT` - The IP and Port that the Bamboo web server will listen on.
 
* `BAMBOO_ZK_HOST` - A comma delimited list of the Zookeeper servers that will house the Bamboo-state.

* `BAMBOO_ZK_PATH` - The Zookeeper path that Bamboo will store it's state in.

* `MARATHON_ENDPOINT` - A comma delimited list of the Marathon servers that Bamboo will subscribe to for events.

* `HAPROXY_TEMPLATE_PATH` - The path to the HAproxy config template.

* `HAPROXY_OUTPUT_PATH` - The path to the HAproxy config file (**required** even if specified in the configuration file).

* `HAPROXY_RELOAD_CMD` - The command used to restart the HAproxy service.

For more information on the available commands, see either the [Bamboo service section](#bamboo) or the [Bamboo project itself](https://github.com/QubitProducts/bamboo).


**Bamboo Configuration File Example**
```
{
  "Marathon": {
    "Endpoint": "http://10.10.0.11:8080,http://10.10.0.12:8080,http://10.10.0.13:8080"
  },

  "Bamboo": {
    "Endpoint": "http://10.10.0.21:8000",
    "Zookeeper": {
      "Host": "10.10.0.11:2181,10.10.0.12:2181,10.10.0.13:2181",
      "Path": "/marathon-haproxy/state",
      "ReportingDelay": 5
    }
  },

  "HAProxy": {
    "TemplatePath": "/opt/bamboo/config/haproxy.tmplt",
    "OutputPath": "/etc/haproxy/haproxy.cfg",
    "ReloadCommand": "iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done"
  },

  "StatsD": {
    "Enabled": false,
    "Host": "localhost:8125",
    "Prefix": "bamboo-server.development."
  }
}
```

---

##### Example Run Command

**Master**
```
docker run -d --net=host --cap-add NET_ADMIN \
-e ENVIRONMENT=production \
-e PARENT_HOST=$(hostname) \
-e BAMBOO_BIND_ADDRESS="10.10.0.2:8000" \
-e BAMBOO_ENDPOINT="http://10.10.0.21:8000" \
-e BAMBOO_ZK_HOST="10.10.0.11:2181,10.10.0.12:2181,10.10.0.13:2181" \
-e BAMBOO_ZK_PATH="/marathon-haproxy/state"
-e MARATHON_ENDPOINT="http://10.10.0.11:8080,http://10.10.0.12:8080,http://10.10.0.13:8080" \
-e HAPROXY_TEMPLATE_PATH="/opt/bamboo/config/haproxy.tmplt" \
-e HAPROXY_OUTPUT_PATH="/etc/haproxy/haproxy.cfg" \
-e HAPROXY_RELOAD_CMD="iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done"
-e STATSD_ENABLED="false" \
-e KEEPALIVED_STATE=MASTER \
-e KEEPALIVED_INTERFACE=eth0 \
-e KEEPALIVED_VIRTUAL_ROUTER_ID=1 \
-e KEEPALIVED_VRRP_UNICAST_BIND="10.10.0.21" \
-e KEEPALIVED_VRRP_UNICAST_PEER="10.10.0.22" \
-e KEEPALIVED_TRACK_INTERFACE_1=eth0 \
-e KEEPALIVED_TRACK_INTERFACE_2=eth1 \
-e KEEPALIVED_VIRTUAL_IPADDRESS_1="10.10.0.2/24 dev eth0" \
-e KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1="172.16.1.10/24 dev eth1" \
bamboo
```

**Backup**
```
docker run -d --net=host --cap-add NET_ADMIN  \
-e ENVIRONMENT=production \
-e PARENT_HOST=$(hostname) \
-e BAMBOO_BIND_ADDRESS="10.10.0.2:8000" \
-e BAMBOO_ENDPOINT="http://10.10.0.2:8000" \
-e BAMBOO_ZK_HOST="10.10.0.11:2181,10.10.0.12:2181,10.10.0.13:2181" \
-e BAMBOO_ZK_PATH="/marathon-haproxy/state"
-e MARATHON_ENDPOINT="http://10.10.0.11:8080,http://10.10.0.12:8080,http://10.10.0.13:8080" \
-e HAPROXY_TEMPLATE_PATH="/opt/bamboo/config/haproxy.tmplt" \
-e HAPROXY_OUTPUT_PATH="/etc/haproxy/haproxy.cfg" \
-e HAPROXY_RELOAD_CMD="iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done"
-e STATSD_ENABLED="false" \
-e KEEPALIVED_STATE=BACKUP \
-e KEEPALIVED_INTERFACE=eth0 \
-e KEEPALIVED_VIRTUAL_ROUTER_ID=1 \
-e KEEPALIVED_VRRP_UNICAST_BIND="10.10.0.22" \
-e KEEPALIVED_VRRP_UNICAST_PEER="10.10.0.21" \
-e KEEPALIVED_TRACK_INTERFACE_1=eth0 \
-e KEEPALIVED_TRACK_INTERFACE_2=eth1 \
-e KEEPALIVED_VIRTUAL_IPADDRESS_1="10.10.0.2/24 dev eth0" \
-e KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1="172.16.1.10/24 dev eth1" \
bamboo
```

---

##### Example Marathon App Definition

**Master**
```
{
    "id": "/bamboo/master",
    "instances": 1,
    "cpus": 1,
    "mem": 512,
    "constraints": [
        [
            "hostname",
            "CLUSTER",
            "10.10.0.21"
        ]
    ],
    "container": {
        "type": "DOCKER",
        "docker": {
            "image": "registry.address/mesos/bamboo",
            "network": "HOST",
            "parameters": [
                {
                    "key": "cap-add",
                    "value": "NET_ADMIN"
                }
            ]
        }
    },
    "env": {
        "ENVIRONMENT": "production",
        "APP_NAME": "bamboo",
        "PARENT_HOST": "mesos-proxy-01",
        "BAMBOO_BIND_ADDRESS": "10.10.0.2:8000",
        "BAMBOO_ENDPOINT": "http://10.10.0.2:8000",
        "BAMBOO_ZK_HOST": "10.10.0.11:2181,10.10.0.12:2181,10.10.0.13:2181",
        "BAMBOO_ZK_PATH": "/marathon-haproxy/state",
        "MARATHON_ENDPOINT": "http://10.10.0.11:8080,http://10.10.0.12:8080,http://10.10.0.13:8080",
        "HAPROXY_TEMPLATE_PATH": "/opt/bamboo/config/haproxy.tmplt",
        "HAPROXY_OUTPUT_PATH": "/etc/haproxy/haproxy.cfg",
        "HAPROXY_RELOAD_CMD": "iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done",
        "STATSD_ENABLED": "false",
        "KEEPALIVED_STATE": "MASTER",
        "KEEPALIVED_INTERFACE": "eth0",
        "KEEPALIVED_VIRTUAL_ROUTER_ID": "1",
        "KEEPALIVED_VRRP_UNICAST_BIND": "10.10.0.21",
        "KEEPALIVED_VRRP_UNICAST_PEER": "10.10.0.22",
        "KEEPALIVED_TRACK_INTERFACE_1": "eth0",
        "KEEPALIVED_TRACK_INTERFACE_2": "eth1",
        "KEEPALIVED_VIRTUAL_IPADDRESS_1": "10.10.0.2/24 dev eth0",
        "KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1": "172.16.1.10/24 dev eth1"
    },
    "uris": [
      "file:///docker.tar.gz"
    ]
}
```

**Backup**
```
{
    "id": "/bamboo/backup",
    "instances": 1,
    "cpus": 1,
    "mem": 512,
    "constraints": [
        [
            "hostname",
            "CLUSTER",
            "10.10.0.22"
        ]
    ],
    "container": {
        "type": "DOCKER",
        "docker": {
            "image": "registry.address/mesos/bamboo",
            "network": "HOST",
            "parameters": [
                {
                    "key": "cap-add",
                    "value": "NET_ADMIN"
                }
            ]
        }
    },
    "env": {
        "ENVIRONMENT": "production",
        "APP_NAME": "bamboo",
        "PARENT_HOST": "mesos-proxy-02",
        "BAMBOO_BIND_ADDRESS": "10.10.0.2:8000",
        "BAMBOO_ENDPOINT": "http://10.10.0.2:8000",
        "BAMBOO_ZK_HOST": "10.10.0.11:2181,10.10.0.12:2181,10.10.0.13:2181",
        "BAMBOO_ZK_PATH": "/marathon-haproxy/state",
        "MARATHON_ENDPOINT": "http://10.10.0.11:8080,http://10.10.0.12:8080,http://10.10.0.13:8080",
        "HAPROXY_TEMPLATE_PATH": "/opt/bamboo/config/haproxy.tmplt",
        "HAPROXY_OUTPUT_PATH": "/etc/haproxy/haproxy.cfg",
        "HAPROXY_RELOAD_CMD": "iptables -I INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; sleep 0.2; supervisorctl restart haproxy; iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP; done",
        "STATSD_ENABLED": "false",
        "KEEPALIVED_STATE": "BACKUP",
        "KEEPALIVED_INTERFACE": "eth0",
        "KEEPALIVED_VIRTUAL_ROUTER_ID": "1",
        "KEEPALIVED_VRRP_UNICAST_BIND": "10.10.0.22",
        "KEEPALIVED_VRRP_UNICAST_PEER": "10.10.0.21",
        "KEEPALIVED_TRACK_INTERFACE_1": "eth0",
        "KEEPALIVED_TRACK_INTERFACE_2": "eth1",
        "KEEPALIVED_VIRTUAL_IPADDRESS_1": "10.10.0.2/24 dev eth0",
        "KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1": "172.16.1.10/24 dev eth1"
    },
    "uris": [
      "file:///docker.tar.gz"
    ]
}
```



* **Note:** The example assumes a v1.6+ version of docker or a v2 version of the docker registry. For information on using an older version or connecting to a v1 registry, please see the [private registry](https://mesosphere.github.io/marathon/docs/native-docker-private-registry.html) section of the Marathon documentation.


---
---


### Modification and Anatomy of the Project

**File Structure**
The directory `skel` in the project root maps to the root of the filesystem once the container is built. Files and folders placed there will map to their corrisponding location within the container.

**Init**
The init script (`./init.sh`) found at the root of the directory is the entry process for the container. It's role is to simply set specific environment variables and modify any subsiquently required configuration files.

**Supervisord**
All supervisord configs can be found in `/etc/supervisor/conf.d/`. Services by default will redirect their stdout to `/dev/fd/1` and stderr to `/dev/fd/2` allowing for service's console output to be displayed. Most applications can log to both stdout and their respecively specified log file.

In some cases (such as with zookeeper), it is possible to specify different logging levels and formats for each location.

**Note:** rsyslog redirects to `/dev/null` unless debugging is enabled. This is to prevent unnecessary chatter from going to the console.


**Bamboo**
Bamboo's configuration information can be found in `/opt/bamboo/config`.

**Logstash-Forwarder**
The Logstash-Forwarder binary and default configuration file can be found in `/skel/opt/logstash-forwarder`. It is ideal to bake the Logstash Server certificate into the base container at this location. If the certificate is called `logstash-forwarder.crt`, the default supplied Logstash-Forwarder config should not need to be modified, and the server setting may be passed through the `SERVICE_LOGSTASH_FORWARDER_ADDRESS` environment variable.

In practice, the supplied Logstash-Forwarder config should be used as an example to produce one tailored to each deployment.

---
---

### Important Environment Variables

Below is the minimum list of variables to be aware of when deploying the Bamboo container.

##### Defaults

| **Variable**                      | **Default**                           |
|-----------------------------------|---------------------------------------|
| `ENVIRONMENT_INIT`                |                                       |
| `APP_NAME`                        | `bamboo`                              |
| `ENVIRONMENT`                     | `local`                               |
| `PARENT_HOST`                     | `unknown`                             |
| `BAMBOO_BIND_ADDRESS`             | `0.0.0.0:8000`                        |
| `BAMBOO_CONF`                     | `/opt/bamboo/config/production.json`  |
| `HAPROXY_OUTPUT_PATH`             | `/etc/haproxy/haproxy.cfg`            |
| `SERVICE_KEEPALIVED`              |                                       |
| `SERVICE_KEEPALIVED_CONF`         | `/etc/keepalived/keepalived.conf`     |
| `KEEPALIVED_AUTOCONF`             | `enabled`                             |
| `SERVICE_LOGSTASH_FORWARDER`      |                                       |
| `SERVICE_LOGSTASH_FORWARDER_CONF` | `/opt/logstash-forwarder/bamboo.conf` |
| `SERVICE_REDPILL`                 |                                       |
| `SERVICE_REPILL_MONITOR`          | `bamboo,haproxy,keepalived`           |
| `SERVICE_RSYSLOG`                 | `enabled`                             |
| `SERVICE_RSYSLOG_CONF`            | `/etc/rsyslog.conf`                   |

##### Description

* `ENVIRONMENT_INIT` - If set, and the file path is valid. This will be sourced and executed before **ANYTHING** else. Useful if supplying an environment file or need to query a service such as consul to populate other variables.

* `APP_NAME` - A brief description of the container. If Logstash-Forwarder is enabled, this will populate the `app_name` field in the Logstash-Forwarder configuration file.

* `ENVIRONMENT` - Sets defaults for several other variables based on the current running environment. Please see the [environment](#environment) section for further information. If logstash-forwarder is enabled, this value will populate the `environment` field in the logstash-forwarder configuration file.

* `PARENT_HOST` - The name of the parent host. If Logstash-Forwarder is enabled, this will populate the `parent_host` field in the Logstash-Forwarder configuration file.

* `BAMBOO_BIND_ADDRESS` - The IP in which Bamboo will bind to.

* `BAMBOO_CONF` - The path to the Bamboo json config file.

* `HAPROXY_OUTPUT_PATH` - The path to the HAproxy config file (**required** even if specified in the configuration file).

* `SERVICE_KEEPALIVED` - Enables or Disables the Keepalived service. Set automatically depending on the `ENVIRONMENT`. See the Environment section below.  (**Options:** `enabled` or `disabled`)

* `SERVICE_KEEPALIVED_CONF` - The path to keepalived config.

* `KEEPALIVED_AUTOCONF` - Enables or disables Keepalived autoconfiguration. (**Options:** `enabled` or `disabled`)

* `SERVICE_LOGSTASH_FORWARDER` - Enables or disables the Logstash-Forwarder service. Set automatically depending on the `ENVIRONMENT`. See the Environment section below.  (**Options:** `enabled` or `disabled`)

* `SERVICE_LOGSTASH_FORWARDER_CONF` - The path to the logstash-forwarder configuration.

* `SERVICE_REDPILL` - Enables or disables the Redpill service. Set automatically depending on the `ENVIRONMENT`. See the Environment section below.  (**Options:** `enabled` or `disabled`)

* `SERVICE_REDPILL_MONITOR` - The name of the supervisord service(s) that the Redpill service check script should monitor.

* `SERVICE_RSYSLOG` - Enables or disables the rsyslog service. This will automatically be set depending on what other services are enabled. (**Options:** `enabled` or `disabled`)

* `SERVICE_RSYSLOG_CONF` - The path to the rsyslog configuration file.

---


#### Environment

* `local` (default)

| **Variable**                 | **Default**                                           |
|------------------------------|-------------------------------------------------------|
| `SERVICE_KEEPALIVED`         | `disabled`                                            |
| `SERVICE_LOGSTASH_FORWARDER` | `disabled`                                            |
| `SERVICE_REDPILL`            | `enabled`                                             |
| `SERVICE_HAPROXY_CMD`        | `/usr/sbin/haproxy -d -f $HAPROXY_OUTPUT_PATH`        |
| `SERVICE_KEEPALIVED_CMD`     | `/usr/sbin/keepalived -n -f $SERVICE_KEEPALIVED_CONF` |

* `prod`|`production`|`dev`|`development`

| **Variable**                 | **Default**                                           |
|------------------------------|-------------------------------------------------------|
| `SERVICE_KEEPALIVED`         | `enabled`                                             |
| `SERVICE_LOGSTASH_FORWARDER` | `enabled`                                             |
| `SERVICE_REDPILL`            | `enabled`                                             |
| `SERVICE_HAPROXY_CMD`        | `/usr/sbin/haproxy -d -f $HAPROXY_OUTPUT_PATH`        |
| `SERVICE_KEEPALIVED_CMD`     | `/usr/sbin/keepalived -n -f $SERVICE_KEEPALIVED_CONF` |

* `debug`

| **Variable**                 | **Default**                                                 |
|------------------------------|-------------------------------------------------------------|
| `SERVICE_KEEPALIVED`         | `enabled`                                                   |
| `SERVICE_LOGSTASH_FORWARDER` | `disabled`                                                  |
| `SERVICE_REDPILL`            | `disabled`                                                  |
| `SERVICE_HAPROXY_CMD`        | `/usr/sbin/haproxy -db -f $HAPROXY_OUTPUT_PATH`             |
| `SERVICE_KEEPALIVED_CMD`     | `/usr/sbin/keepalived -n -D -l -f $SERVICE_KEEPALIVED_CONF` |


---
---

### Service Configuration

---

### Bamboo

Bamboo is a daemon providing service-discovery and HAproxy autoconfiguration for tasks managed with Marathon. As it is undergoing fairly rapid development, please see their [Github Project Page](https://github.com/QubitProducts/bamboo) for an up to date list of configuration parameters.

The below environment variables have either been added via the init script, or must be provided.

##### Defaults

| **Variable**          | **Default**                                                          |
|-----------------------|----------------------------------------------------------------------|
| `BAMBOO_BIND_ADDRESS` | `0.0.0.0:8000`                                                       |
| `BAMBOO_CONF`         | `/opt/bamboo/config/production.json`                                 |
| `HAPROXY_OUTPUT_PATH` | `/etc/haproxy/haproxy.cfg`                                           |
| `SERVICE_BAMBOO_CMD`  | `/opt/bamboo/bamboo -bind=$BAMBOO_BIND_ADDRESS -config=$BAMBOO_CONF` |

##### Description

* `BAMBOO_BIND_ADDRESS` - The IP in which Bamboo will bind to.

* `BAMBOO_CONF` - The path to the Bamboo json config file.

* `HAPROXY_OUTPUT_PATH` - The path to the HAproxy config file (**required** even if specified in the configuration file).

* `SERVICE_BAMBOO_CMD` - The command that is passed to supervisor. If overriding, must be an escaped python string expression. Please see the [Supervisord Command Documentation](http://supervisord.org/configuration.html#program-x-section-settings) for further information.

---

### HAproxy
HAproxy is a small and high performant tcp/http based load balancer. In the Bamboo container - much of HAproxy's configuration is left to Bamboo making the available service controls for HAproxy very small. For logging, it is dependant on Rsyslog being available.


##### Defaults

| **Variable**          | **Default**                |
|-----------------------|----------------------------|
| `HAPROXY_OUTPUT_PATH` | `/etc/haproxy/haproxy.cfg` |
| `SERVICE_HAPROXY_CMD` | `enabled`                  |

##### Description

* `HAPROXY_OUTPUT_PATH` - The path to the HAproxy config file (**required** even if specified in the configuration file).

* `SERVICE_HAPROXY_CMD` - The command that is passed to supervisor. If overriding, must be an escaped python string expression. Please see the [Supervisord Command Documentation](http://supervisord.org/configuration.html#program-x-section-settings) for further information.

---

### Rsyslog
Rsyslog is a high performance log processing daemon. 

Both HAproxy and Keepalved's logging capability are dependant on the rsyslog service. Rsyslog is enabled in all configurations by default. For any modifications to the config, it is best to edit the rsyslog configs directly (`/etc/rsyslog.conf` and `/etc/rsyslog.d/*`).

##### Defaults

| **Variable**                      | **Default**                                      |
|-----------------------------------|--------------------------------------------------|
| `SERVICE_RSYSLOG`                 | `enabled`                                        |
| `SERVICE_RSYSLOG_CONF`            | `/etc/rsyslog.conf`                              |
| `SERVICE_RSYSLOG_CMD`             | `/usr/sbin/rsyslogd -n -f $SERVICE_RSYSLOG_CONF` |

##### Description

* `SERVICE_RSYSLOG` - Enables or disables the rsyslog service. This will automatically be set depending on what other services are enabled. (**Options:** `enabled` or `disabled`)

* `SERVICE_RSYSLOG_CONF` - The path to the rsyslog configuration file.

* `SERVICE_RSYSLOG_CMD` -  The command that is passed to supervisor. If overriding, must be an escaped python string expression. Please see the [Supervisord Command Documentation](http://supervisord.org/configuration.html#program-x-section-settings) for further information.

---

### Keepalived

A battle-tested daemon built to handle load balancing and failover. If `KEEPALIVED_AUTOCONF` is enabed, it will autogenerate a unicaist based failover configuration with a minimal amount of user supplied information. For specific information on Keepalived, please see the man page on [keepalived.conf](http://linux.die.net    /man/5/keepalived.conf) or the [Keepalived User Guide](http://www.keepalived.org/pdf/UserGuide.pdf).

#### Keepalived Autoconfiguration Options

##### Defaults

| **Variable**                                | **Default**                        |
|---------------------------------------------|------------------------------------|
| `KEEPALIVED_AUTOCONF`                       | `enabled`                          |
| `KEEPALIVED_STATE`                          | `MASTER`                           |
| `KEEPALIVED_PRIORITY`                       | `200`                              |
| `KEEPALIVED_INTERFACE`                      | `eth0`                             |
| `KEEPALIVED_VIRTUAL_ROUTER_ID`              | `1`                                |
| `KEEPALIVED_ADVERT_INT`                     | `1`                                |
| `KEEPALIVED_AUTH_PASS`                      | `pwd$KEEPALIVED_VIRTUAL_ROUTER_ID` |
| `KEEPALIVED_VRRP_UNICAST_BIND`              |                                    |
| `KEEPALIVED_VRRP_UNICAST_PEER`              |                                    |
| `KEEPALIVED_TRACK_INTERFACE_###`            |                                    |
| `KEEPALIVED_VIRTUAL_IPADDRESS_###`          |                                    |
| `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_###` |                                    |

##### Description

* `KEEPALIVED_AUTOCONF` - Enables or Disables Keepalived autoconfiguration. (**Options:** `enabled` or `disabled`)

* `KEEPALIVED_STATE` - Defines the server role as Master or Backup. (**Options:** `MASTER` or `BACKUP`).

* `KEEPALIVED_PRIORITY` - Election value, the server configured with the highest priority will become the Master.

* `KEEPALIVED_INTERFACE` - The host interface that keepalived will monitor and use for VRRP traffic.

* `KEEPALIVED_VIRTUAL_ROUTER_ID` - A unique number from 0 to 255 that should identifiy the VRRP group. Master and Backup should have the same value. Multiple instances of keepalived can be run on the same host, but each pair **MUST** have a unique virtual router id.

* `KEEPALIVED_ADVERT_INT` - The VRRP advertisement interval (in seconds).

* `KEEPALIVED_AUTH_PASS` - A shared password used to authenticate each node in a VRRP group (**Note:** If password is longer than 8 characters, only the first 8 characters are used).

* `KEEPALIVED_VRRP_UNICAST_BIND` - The IP on the host that the keepalived daemon should bind to. **Note:** If not specified, it will be the first IP bound to the interface specified in `$KEEPALIVED_INTERFACE`

* `KEEPALIVED_VRRP_UNICAST_PEER` - The IP of the peer in the VRRP group. (**Required**)

* `KEEPALIVED_TRACK_INTERFACE_###` - An interface that's state should be monitored (e.g. eth0). More than one can be supplied as long as the variable name ends in a number from 0-999.

* `KEEPALIVED_VIRTUAL_IPADDRESS_###` - An instance of an address that will be monitored and failed over from one host to another. These should be a quoted string in the form of: `<IPADDRESS>/<MASK> brd <BROADCAST_IP> dev <DEVICE> scope <SCOPE> label <LABEL>` At a minimum the ip address, mask and device should be specified e.g. `KEEPALIVED_VIRTUAL_IPADDRESS_1="10.10.0.2/24 dev eth0"`. More than one can be supplied as long as the variable name ends in a number from 0-999. **Note:** Keepalived has a hard limit of **20** addresses that can be monitored. More can be failed over with the monitored addresses via `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_###`. (**Required**)

* `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_###` - An instance of an address that will be failed over with the monitored addresses supplied via `KEEPALIVED_VIRTUAL_IPADDRESS_###`.  These should be a quoted string in the form of: `<IPADDRESS>/<MASK> brd <BROADCAST_IP> dev <DEVICE> scope <SCOPE> label <LABEL>` At a minimum the ip address, mask and device should be specified e.g. `KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_1="172.16.1.20/24 dev eth1"`. More than one can be supplied as long as the variable name ends in a number from 0-999.

##### Example Autogenerated Keepalived Master Config
```
vrrp_instance MAIN {
  state MASTER
  interface eth0
  vrrp_unicast_bind 10.10.0.21
  vrrp_unicast_peer 10.10.0.22
  virtual_router_id 1
  priority 200
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass pwd1
  }
  virtual_ipaddress {
    10.10.0.2/24 dev eth0
  }
  virtual_ipaddress_excluded {
    172.16.1.20/24 dev eth1
  }
  track_interface {
    eth0
    eth1
  }
}

```

##### Example Autogenerated Keepalived Backup Config
```
vrrp_instance MAIN {
  state BACKUP
  interface eth0
  vrrp_unicast_bind 10.10.0.22
  vrrp_unicast_peer 10.10.0.21
  virtual_router_id 1
  priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass pwd1
  }
  virtual_ipaddress {
    10.10.0.2/24 dev eth0
  }
  virtual_ipaddress_excluded {
    172.16.1.20/24 dev eth1
  }
  track_interface {
    eth0
    eth1
  }
}

```
---

### Logstash-Forwarder

Logstash-Forwarder is a lightweight application that collects and forwards logs to a logstash server endpoint for further processing. For more information see the [Logstash-Forwarder](https://github.com/elastic/logstash-forwarder) project.


#### Logstash-Forwarder Environment Variables

##### Defaults

| **Variable**                         | **Default**                                                                             |
|--------------------------------------|-----------------------------------------------------------------------------------------|
| `SERVICE_LOGSTASH_FORWARDER`         |                                                                                         |
| `SERVICE_LOGSTASH_FORWARDER_CONF`    | `/opt/logstash-forwarer/bamboo.conf`                                                    |
| `SERVICE_LOGSTASH_FORWARDER_ADDRESS` |                                                                                         |
| `SERVICE_LOGSTASH_FORWARDER_CERT`    |                                                                                         |
| `SERVICE_LOGSTASH_FORWARDER_CMD`     | `/opt/logstash-forwarder/logstash-forwarder -config=”$SERVICE_LOGSTASH_FORWARDER_CONF”` |

##### Description

* `SERVICE_LOGSTASH_FORWARDER` - Enables or disables the Logstash-Forwarder service. Set automatically depending on the `ENVIRONMENT`. See the Environment section.  (**Options:** `enabled` or `disabled`)

* `SERVICE_LOGSTASH_FORWARDER_CONF` - The path to the logstash-forwarder configuration.

* `SERVICE_LOGSTASH_FORWARDER_ADDRESS` - The address of the Logstash server.

* `SERVICE_LOGSTASH_FORWARDER_CERT` - The path to the Logstash-Forwarder server certificate.

* `SERVICE_LOGSTASH_FORWARDER_CMD` - The command that is passed to supervisor. If overriding, must be an escaped python string expression. Please see the [Supervisord Command Documentation](http://supervisord.org/configuration.html#program-x-section-settings) for further information.

---

### Redpill

Redpill is a small script that performs status checks on services managed through supervisor. In the event of a failed service (FATAL) Redpill optionally runs a cleanup script and then terminates the parent supervisor process.


#### Redpill Environment Variables

##### Defaults

| **Variable**               | **Default**                 |
|----------------------------|-----------------------------|
| `SERVICE_REDPILL`          |                             |
| `SERVICE_REDPILL_MONITOR`  | `bamboo,haproxy,keepalived` |
| `SERVICE_REDPILL_INTERVAL` |                             |
| `SERVICE_REDPILL_CLEANUP`  |                             |

##### Description

* `SERVICE_REDPILL` - Enables or disables the Redpill service. Set automatically depending on the `ENVIRONMENT`. See the Environment section.  (**Options:** `enabled` or `disabled`)

* `SERVICE_REDPILL_MONITOR` - The name of the supervisord service(s) that the Redpill service check script should monitor. 

* `SERVICE_REDPILL_INTERVAL` - The interval in which Redpill polls supervisor for status checks. (Default for the script is 30 seconds)

* `SERVICE_REDPILL_CLEANUP` - The path to the script that will be executed upon container termination. For OpenVPN this should clear any iptables rules from the host.


##### Redpill Script Help Text
```
root@c90c98ae31e1:/# /opt/scripts/redpill.sh --help
Redpill - Supervisor status monitor. Terminates the supervisor process if any specified service enters a FATAL state.

-c | --cleanup    Optional path to cleanup script that should be executed upon exit.
-h | --help       This help text.
-i | --inerval    Optional interval at which the service check is performed in seconds. (Default: 30)
-s | --service    A comma delimited list of the supervisor service names that should be monitored.
```

---
---

### Troubleshooting

In the event of an issue, the `ENVIRONMENT` variable can be set to `debug`.  This will stop the container from shipping logs and prevent it from terminating if one of the services enters a failed state.

In addition to disabling Logstash-Forwarder, and Redpill the supervisor config for HAproxy will be modified to route logs to the console.



