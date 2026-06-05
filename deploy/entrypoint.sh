#!/usr/bin/env bash
NAME="djangoblog"
DJANGODIR=/code/djangoblog
USER=root
GROUP=root
NUM_WORKERS=1
DJANGO_WSGI_MODULE=djangoblog.wsgi


echo "Starting $NAME as `whoami`"

cd $DJANGODIR

export PYTHONPATH=$DJANGODIR:$PYTHONPATH

python manage.py makemigrations && \
  python manage.py migrate && \
  python manage.py collectstatic --noinput  && \
  echo "Verifying Vite build artifacts..." && \
  ls -la blog/static/blog/dist/css/ && \
  ls -la blog/static/blog/dist/js/ && \
  echo "Vite manifest content:" && \
  cat blog/static/blog/dist/.vite/manifest.json && \
  echo "Copying .vite directory to collectedstatic..." && \
  mkdir -p collectedstatic/blog/dist/.vite && \
  cp -r blog/static/blog/dist/.vite/* collectedstatic/blog/dist/.vite/ && \
  python manage.py compress --force

if [ -n "$DJANGO_ELASTICSEARCH_HOST" ]; then
  echo "Elasticsearch host detected: $DJANGO_ELASTICSEARCH_HOST"
  echo "Waiting for Elasticsearch to be ready..."

  ES_HOST=$(echo "$DJANGO_ELASTICSEARCH_HOST" | sed 's|^http://||' | sed 's|^https://||')
  MAX_RETRIES=60
  RETRY_COUNT=0

  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf "http://${ES_HOST}/_cluster/health" > /dev/null 2>&1; then
      echo "Elasticsearch is ready!"
      break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Elasticsearch not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), waiting..."
    sleep 5
  done

  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "WARNING: Elasticsearch did not become ready after $MAX_RETRIES attempts. Proceeding anyway..."
  fi
fi

python manage.py build_index && \
  python manage.py compilemessages  || exit 1

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
--name $NAME \
--workers $NUM_WORKERS \
--user=$USER --group=$GROUP \
--bind 0.0.0.0:8000 \
--log-level=debug \
--log-file=- \
--worker-class gevent \
--threads 4