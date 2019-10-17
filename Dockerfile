From openjdk:8
###############################################################################
#                                INSTALLATION
###############################################################################

### install prerequisites (cURL, gosu, JDK, tzdata)

RUN set -x \
 && apt update -qq \
 && apt install -qqy --no-install-recommends ca-certificates curl gosu tzdata openjdk-8-jdk \
 && apt clean \
 && rm -rf /var/lib/apt/lists/* \
 && gosu nobody true \
 && set +x

COPY "APP_VERSION.yaml" "/"


## install Kibana

ENV \
 KIBANA_HOME=/opt/kibana \
 KIBANA_GID=993 \
 KIBANA_UID=993

 RUN KIBANA_VERSION=$(cat /APP_VERSION.yaml) \
 && KIBANA_PACKAGE=kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz && echo "$KIBANA_PACKAGE" \
 && mkdir ${KIBANA_HOME} \
 && curl -O https://artifacts.elastic.co/downloads/kibana/${KIBANA_PACKAGE} \
 && curl https://artifacts.elastic.co/downloads/kibana/kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz.sha512 | cut -d ' ' -f1  > ${KIBANA_HOME}/sha_info \
 && shasum -a 512 $KIBANA_PACKAGE | cut -d ' ' -f1 > ${KIBANA_HOME}/files_sha \
 && cmp ${KIBANA_HOME}/sha_info ${KIBANA_HOME}/files_sha && if [[ $? -ne 0 ]]; then echo "sha do not match, exiting..." && exit 1; fi \
 && tar xzf ${KIBANA_PACKAGE} -C ${KIBANA_HOME} --strip-components=1 \
 && rm -f ${KIBANA_PACKAGE} \
 && groupadd -r kibana -g ${KIBANA_GID} \
 && useradd -r -s /usr/sbin/nologin -d ${KIBANA_HOME} -c "Kibana service user" -u ${KIBANA_UID} -g kibana kibana \
 && mkdir -p /var/log/kibana \
 && chown -R kibana:kibana ${KIBANA_HOME} /var/log/kibana


###############################################################################
#                              START-UP SCRIPTS
###############################################################################

### Kibana ##############

ADD ./kibana-init /etc/init.d/kibana
RUN sed -i -e 's#^KIBANA_HOME=$#KIBANA_HOME='$KIBANA_HOME'#' /etc/init.d/kibana \
 && chmod +x /etc/init.d/kibana


###############################################################################
#                               CONFIGURATION
###############################################################################

ADD ./kibana.yml ${KIBANA_HOME}/config/kibana.yml

###############################################################################
#                                   START
###############################################################################

ADD ./start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 5601
VOLUME /var/lib/kibana

CMD [ "/usr/local/bin/start.sh" ]
