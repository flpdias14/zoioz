FROM alpine:latest
LABEL maintainer="Modcs Research Group <flpdias14@gmail.com>"
LABEL description="Zoioz is to the monitoring of docker containers."

# Basic packages
ENV PACKAGES \
        curl \
        jq

RUN apk update

RUN apk add ${PACKAGES}


COPY main.sh /sbin/main.sh
COPY entrypoint.sh /sbin/entrypoint.sh
COPY /etc/timezone /etc/timezone

RUN chmod 755 entrypoint.sh 

RUN chmod 755 main.sh



VOLUME [ "/var/www/files"]

CMD ["/sbin/entrypoint.sh"]
