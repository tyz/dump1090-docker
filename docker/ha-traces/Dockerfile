# syntax=docker/dockerfile:1

FROM python:3-slim

RUN python3 -m pip install requests

WORKDIR /app

COPY ha-traces.py .

RUN chmod 755 ha-traces.py

ENTRYPOINT ["/app/ha-traces.py"]
