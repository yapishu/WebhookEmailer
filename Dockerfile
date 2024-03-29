# Planet sale hook
FROM python:3.9-slim-buster as hook

RUN apt-get update && apt-get --no-install-recommends install -y \
    curl wget vim python3-pip procps apt-utils git lua5.2 sqlite3
COPY ./requirements.txt /app/requirements.txt
RUN pip3 install -r /app/requirements.txt
COPY ./app.py /app
RUN git clone https://github.com/textprotocol/sigil /app/sigil

EXPOSE 5000
ENTRYPOINT ["python3","/app/app.py"]