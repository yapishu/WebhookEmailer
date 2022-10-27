# Planet sale hook
FROM python:3.9-slim-buster as sale-hook

RUN apt-get update && apt-get --no-install-recommends install -y \
    curl wget vim python3-pip procps apt-utils git
COPY ./requirements.txt /app/requirements.txt
RUN pip3 install -r /app/requirements.txt
COPY ./ /app
RUN git clone https://github.com/textprotocol/sigil /app
RUN mkdir -p ~/.ssh/

EXPOSE 8090
ENTRYPOINT ["python3","/app/app.py","-e","prod"]