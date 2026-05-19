FROM alpine:3.20

RUN apk add --no-cache rsyslog

COPY rsyslog.conf /etc/rsyslog.conf

EXPOSE 514/tcp 514/udp

CMD ["rsyslogd", "-n", "-f", "/etc/rsyslog.conf"]
