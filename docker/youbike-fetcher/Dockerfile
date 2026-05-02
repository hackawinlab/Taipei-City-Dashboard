FROM python:3.11-slim

RUN pip install --no-cache-dir requests psycopg2-binary

WORKDIR /app
COPY fetch_ubike.py .

CMD ["python", "-u", "fetch_ubike.py"]
