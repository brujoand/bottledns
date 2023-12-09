FROM alpine:latest

RUN apk --no-cache add jq bash dnsmasq curl

COPY bottledns.sh /bottledns.sh
COPY etc/dnsmasq.conf /etc/dnsmasq.conf
COPY etc/bottledns.hosts /etc/bottledns.hosts

RUN chmod +x /bottledns.sh

ENTRYPOINT ["/bottledns.sh"]
