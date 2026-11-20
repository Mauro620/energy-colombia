FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PIP_DEFAULT_TIMEOUT=120 PIP_RETRIES=8
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
