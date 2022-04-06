FROM almir/webhook AS netsub-planetshooter
LABEL authors="~matwet <matwet@subject.network>"

COPY webhookMailer.sh /etc/webhook/webhookMailer.sh
COPY getStatus.sh /etc/webhook/getStatus.sh

COPY emailer.json /etc/webhook/emailer.json
RUN mkdir -p /etc/webhook/data
RUN chmod +x /etc/webhook/webhookMailer.sh
RUN chmod +x /etc/webhook/getStatus.sh

RUN sed -i 's/AUTH_CODE_VAR/`echo $AUTH_CODE_VAR`/g' /etc/webhook/webhookMailer.sh
RUN sed -i 's/CSV_FILE_VAR/$CSV_FILE_VAR/g' /etc/webhook/webhookMailer.sh
RUN sed -i 's/FROM_EMAIL_VAR/${FROM_EMAIL_VAR}/g' /etc/webhook/webhookMailer.sh
RUN sed -i 's/FROM_NAME_VAR/${FROM_NAME_VAR}/g' /etc/webhook/webhookMailer.sh
RUN sed -i 's/SG_API_VAR/${SG_API_VAR}/g' /etc/webhook/webhookMailer.sh
RUN sed -i 's/SG_TEMPLATE_VAR/${SG_TEMPLATE_VAR}/g' /etc/webhook/webhookMailer.sh

CMD ["-verbose", "-hooks=/etc/webhook/emailer.json", "-hotreload"]