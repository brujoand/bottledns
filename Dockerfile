FROM alpine:latest

RUN apk --no-cache add jq bash dnsmasq curl

RUN adduser -D -s /bin/bash bottledns

COPY bottledns.sh /bottledns.sh
COPY etc/dnsmasq.conf /home/bottledns/dnsmasq.conf
COPY etc/bottledns.hosts /home/bottledns/bottledns.hosts

RUN chmod +x /bottledns.sh && \
    chown -R bottledns:bottledns /home/bottledns

USER bottledns

ENTRYPOINT ["/bottledns.sh"]
