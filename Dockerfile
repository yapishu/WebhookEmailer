FROM golang:1.17.1-alpine3.14 AS netsub-planetshooter
LABEL   authors="~matwet <matwet@subject.network>"

RUN apk --no-cache add --update bash sudo vim git wget curl jq sqlite build-deps build-base libc-dev gcc libgcc 'su-exec>=0.2'

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

ENV LOG_LEVEL "verbose"
ENV WEBHOOK_VERSION "2.8.0"

RUN curl -L --silent -o webhook.tar.gz https://github.com/adnanh/webhook/archive/${WEBHOOK_VERSION}.tar.gz && \
    tar -xzf webhook.tar.gz --strip 1 &&  \
    go get -d && \
    go build -o /usr/local/bin/webhook && \
    apk del --purge build-deps && \
    rm -rf /var/cache/apk/* && \
    rm -rf /go

RUN mkdir -p /data/user

COPY webhookMailer.sh /data/webhookMailer.sh
COPY emailer.json /data/emailer.json
COPY getStats.sh /data/getStats.sh

RUN chmod +x /data/webhookMailer.sh
RUN chmod +x /data/getStats.sh

RUN sed -i 's/AUTH_CODE_VAR/${AUTH_CODE_VAR}/g' /data/webhookMailer.sh
RUN sed -i 's/CSV_FILE_VAR/${CSV_FILE_VAR}/g' /data/webhookMailer.sh
RUN sed -i 's/FROM_EMAIL_VAR/${FROM_EMAIL_VAR}/g' /data/webhookMailer.sh
RUN sed -i 's/FROM_NAME_VAR/${FROM_NAME_VAR}/g' /data/webhookMailer.sh
RUN sed -i 's/SG_API_VAR/${SG_API_VAR}/g' /data/webhookMailer.sh
RUN sed -i 's/SG_TEMPLATE_VAR/${SG_TEMPLATE_VAR}/g' /data/webhookMailer.sh

CMD [ "/usr/local/bin/webhook -hooks /data/emailer.json -verbose" ]
