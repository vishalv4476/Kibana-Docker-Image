#!/bin/bash
#
# /usr/local/bin/start.sh
# Start Kibana service
#
## handle termination gracefully

_term() {
  echo "Terminating Kibana"
  service kibana stop
  exit 0
}

trap _term SIGTERM SIGINT

rm -f /var/run/kibana5.pid

## initialise list of log files to stream in console (initially empty)
OUTPUT_LOGFILES=""


## override default time zone (Etc/UTC) if TZ variable is set
if [ ! -z "$TZ" ]; then
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi


## run pre-hooks
if [ -x /usr/local/bin/elk-pre-hooks.sh ]; then
  . /usr/local/bin/elk-pre-hooks.sh
fi


### Kibana

if [ -z "$KIBANA_START" ]; then
  KIBANA_START=1
fi
if [ "$KIBANA_START" -ne "1" ]; then
  echo "KIBANA_START is set to something different from 1, not starting..."
else
  # override NODE_OPTIONS variable if set
  if [ ! -z "$NODE_OPTIONS" ]; then
    awk -v LINE="NODE_OPTIONS=\"$NODE_OPTIONS\"" '{ sub(/^NODE_OPTIONS=.*/, LINE); print; }' /etc/init.d/kibana \
        > /etc/init.d/kibana.new && mv /etc/init.d/kibana.new /etc/init.d/kibana && chmod +x /etc/init.d/kibana
  fi

  service kibana start
  OUTPUT_LOGFILES+="/var/log/kibana/kibana5.log "
fi

# Exit if nothing has been started
if  [ "$KIBANA_START" -ne "1" ]; then
  >&2 echo "Kibana service is not started. Exiting."
  exit 1
fi


## run post-hooks
if [ -x /usr/local/bin/elk-post-hooks.sh ]; then
  ### if Kibana was started...
  if [ "$KIBANA_START" -eq "1" ]; then

  ### ... then wait for Kibana to be up first to ensure that .kibana index is
  ### created before the post-hooks are executed
    # set number of retries (default: 30, override using KIBANA_CONNECT_RETRY env var)
    if ! [[ $KIBANA_CONNECT_RETRY =~ $re_is_numeric ]] ; then
       KIBANA_CONNECT_RETRY=30
    fi

    if [ -z "$KIBANA_URL" ]; then
      KIBANA_URL=http://localhost:5601
    fi

    counter=0
    while [ ! "$(curl ${KIBANA_URL} 2> /dev/null)" -a $counter -lt $KIBANA_CONNECT_RETRY  ]; do
      sleep 1
      ((counter++))
      echo "waiting for Kibana to be up ($counter/$KIBANA_CONNECT_RETRY)"
    done
    if [ ! "$(curl ${KIBANA_URL} 2> /dev/null)" ]; then
      echo "Couldn't start Kibana. Exiting."
      echo "Kibana log follows below."
      cat /var/log/kibana/kibana5.log
      exit 1
    fi
    # wait for Kibana to not only be up but to return 200 OK
    counter=0
    while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' ${KIBANA_URL}/api/status)" != "200" && $counter -lt 30 ]]; do
      sleep 1
      ((counter++))
      echo "waiting for Kibana to respond ($counter/30)"
    done
    if [[ "$(curl -s -o /dev/null -w ''%{http_code}'' ${KIBANA_URL}/api/status)" != "200" ]]; then
      echo "Timed out waiting for Kibana to respond. Exiting."
      echo "Kibana log follows below."
      cat /var/log/kibana/kibana5.log
      exit 1
    fi
  fi

  . /usr/local/bin/elk-post-hooks.sh
fi


touch $OUTPUT_LOGFILES
tail -f $OUTPUT_LOGFILES &
wait
