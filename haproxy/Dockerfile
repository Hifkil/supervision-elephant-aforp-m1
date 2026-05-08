FROM haproxy:2.9-alpine
USER root
RUN apk add --no-cache curl
USER haproxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
