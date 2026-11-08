# Cloud Run image for the Gatelog API. The same image runs migrations as a Cloud Run job:
#   alembic upgrade head   (with DATABASE_OWNER_URL set)
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt google-cloud-secret-manager google-auth
COPY alembic.ini .
COPY migrations ./migrations
COPY app ./app
USER nobody
# Only Google's front end can reach a Cloud Run container, so trust its X-Forwarded-For:
# without this every caller looks like one IP and shares one rate-limit bucket.
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips="*"
