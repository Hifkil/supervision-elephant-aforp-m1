FROM splunk/splunk:9.4

COPY apps/artemis /opt/artemis-splunk-app
COPY entrypoint-artemis.sh /sbin/entrypoint-artemis.sh

USER root
RUN chmod +x /sbin/entrypoint-artemis.sh \
  && chown -R ansible:ansible /opt/artemis-splunk-app
USER ansible

ENTRYPOINT ["/sbin/entrypoint-artemis.sh"]
CMD ["start-service"]
