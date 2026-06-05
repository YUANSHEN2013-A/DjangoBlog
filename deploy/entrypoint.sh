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

wait_for_elasticsearch() {
    if [ -z "$DJANGO_ELASTICSEARCH_HOST" ]; then
        echo "DJANGO_ELASTICSEARCH_HOST not set, skipping ES health check."
        return 0
    fi

    ES_HOST="http://${DJANGO_ELASTICSEARCH_HOST}"
    MAX_RETRIES=60
    RETRY_INTERVAL=5

    echo "Waiting for Elasticsearch at ${ES_HOST} to be available..."
    retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -sf "${ES_HOST}/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null 2>&1; then
            echo "Elasticsearch is ready at ${ES_HOST}."
            return 0
        fi
        retry_count=$((retry_count + 1))
        echo "Elasticsearch not ready yet, retrying in ${RETRY_INTERVAL}s... ($retry_count/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done

    echo "WARNING: Elasticsearch did not become ready after $((MAX_RETRIES * RETRY_INTERVAL))s."
    echo "Continuing without ES - build_index may fail if ES is required."
    return 1
}

wait_for_elasticsearch

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
  python manage.py compress --force && \
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
