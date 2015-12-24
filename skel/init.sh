#!/bin/bash

source /opt/scripts/container_functions.lib.sh

init_vars() {
    
  if [[ $ENVIRONMENT_INIT && -f $ENVIRONMENT_INIT ]]; then
      source "$ENVIRONMENT_INIT"
  fi

  if [[ ! $PARENT_HOST && $HOST ]]; then
    export PARENT_HOST="$HOST"
  fi

  export APP_NAME=${APP_NAME:-bamboo}
  export ENVIRONMENT=${ENVIRONMENT:-local} 
  export PARENT_HOST=${PARENT_HOST:-unknown}

  export BAMBOO_BIND_ADDRESS=${BAMBOO_BIND_ADDRESS:-0.0.0.0:8000}
  export BAMBOO_LOG_FILE=${BAMBOO_LOG_FILE:-/var/log/bamboo/bamboo.log}
  export BAMBOO_CONF=${BAMBOO_CONF:-/opt/bamboo/config/production.json}
  export HAPROXY_OUTPUT_PATH=${HAPROXY_OUTPUT_PATH:-/etc/haproxy/haproxy.cfg}
  
  export KEEPALIVED_AUTOCONF=${KEEPALIVED_AUTOCONF:-enabled}
  export SERVICE_KEEPALIVED_CONF=${SERVICE_KEEPALIVED_CONF:-/etc/keepalived/keepalived.conf}
  export SERVICE_LOGROTATE_CONF=${SERVICE_LOGROTATE_CONF:-/etc/logrotate.conf}
  export SERVICE_LOGSTASH_FORWARDER_CONF=${SERVICE_LOGSTASH_FORWARDER_CONF:-/opt/logstash-forwarder/bamboo.conf}
  export SERVICE_REDPILL_MONITOR=${SERVICE_REDPILL_MONITOR:-"bamboo,haproxy,keepalived"}
  export SERVICE_RSYSLOG=${SERVICE_RSYSLOG:-enabled}

  bamboo_cmd="$(__escape_svsr_txt "/opt/bamboo/bamboo -bind=$BAMBOO_BIND_ADDRESS -config=$BAMBOO_CONF -log=$BAMBOO_LOG_FILE")"
  export SERVICE_BAMBOO_CMD=${SERVICE_BAMBOO_CMD:-"$bamboo_cmd"}

  case "${ENVIRONMENT,,}" in
    prod|production|dev|development)
      export SERVICE_KEEPALIVED=${SERVICE_KEEPALIVED:-enabled}
      export SERVICE_LOGROTATE=${SERVICE_LOGROTATE:-enabled}
      export SERVICE_LOGSTASH_FORWARDER=${SERVICE_LOGSTASH_FORWARDER:-enabled}
      export SERVICE_REDPILL=${SERVICE_REDPILL:-enabled}
      export SERVICE_HAPROXY_CMD=${SERVICE_HAPROXY_CMD:-"/usr/sbin/haproxy -d -f $HAPROXY_OUTPUT_PATH"}
      export SERVICE_KEEPALIVED_CMD=${SERVICE_KEEPALIVED_CMD:-"/usr/sbin/keepalived -n -f $SERVICE_KEEPALIVED_CONF"}
      ;;
    debug)
      export SERVICE_KEEPALIVED=${SERVICE_KEEPALIVED:-enabled}
      export SERVICE_LOGROTATE=${SERVICE_LOGROTATE:-disabled}
      export SERVICE_LOGSTASH_FORWARDER=${SERVICE_LOGSTASH_FORWARDER:-disabled}
      export SERVICE_REDPILL=${SERVICE_REDPILL:-disabled}
      export SERVICE_HAPROXY_CMD=${SERVICE_HAPROXY_CMD:-"/usr/sbin/haproxy -db -f $HAPROXY_OUTPUT_PATH"}
      export SERVICE_KEEPALIVED_CMD=${SERVICE_KEEPALIVED_CMD:-"/usr/sbin/keepalived -n -D -l -f $SERVICE_KEEPALIVED_CONF"}
      sed -e "s|^stdout_logfile=.*|stdout_logfile=/dev/fd/1|g" -i /etc/supervisor/conf.d/haproxy.conf
      sed -e "s|^stderr_logfile=.*|stderr_logfile=/dev/fd/2|g" -i /etc/supervisor/conf.d/haproxy.conf
      ;;
    local|*)
      export SERVICE_KEEPALIVED=${SERVICE_KEEPALIVED:-disabled}
      export SERVICE_LOGROTATE=${SERVICE_LOGROTATE:-enabled}
      export SERVICE_LOGSTASH_FORWARDER=${SERVICE_LOGSTASH_FORWARDER:-disabled}
      export SERVICE_REDPILL=${SERVICE_REDPILL:-enabled}
      export SERVICE_HAPROXY_CMD=${SERVICE_HAPROXY_CMD:-"/usr/sbin/haproxy -d -f $HAPROXY_OUTPUT_PATH"}
      export SERVICE_KEEPALIVED_CMD=${SERVICE_KEEPALIVED_CMD:-"/usr/sbin/keepalived -n -f $SERVICE_KEEPALIVED_CONF"}
      ;;
  esac
}

main() {

  init_vars

  echo "[$(date)][App-Name] $APP_NAME"
  echo "[$(date)][Environment] $ENVIRONMENT"

  __config_service_keepalived
  __config_service_logrotate
  __config_service_logstash_forwarder
  __config_service_redpill
  __config_service_rsyslog

  if [[ ${SERVICE_KEEPALIVED,,} == "enabled" && ${KEEPALIVED_AUTOCONF,,}  == "enabled" ]]; then
    __config_keepalived
    if [[ $? -ne 0 ]]; then
      echo "[$(date)][Keepalived] Error configuring keepalived. Terminating init."
      exit 1
    fi
  fi

  echo "[$(date)][HAProxy][Start-Command] $SERVICE_HAPROXY_CMD"
  echo "[$(date)][Bamboo][Listening-Address] $BAMBOO_BIND_ADDRESS"
  echo "[$(date)][Bamboo][Start-Command] $SERVICE_BAMBOO_CMD"
  
  exec supervisord -n -c /etc/supervisor/supervisord.conf

}

main "$@"
