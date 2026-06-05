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
  python manage.py compress --force && \
  python manage.py compilemessages  || exit 1

if [ -n "$DJANGO_ELASTICSEARCH_HOST" ]; then
    echo "Waiting for Elasticsearch to be available..."
    ES_URL="$DJANGO_ELASTICSEARCH_HOST"
    if [[ $ES_URL != http* ]]; then
        ES_URL="http://$ES_URL"
    fi
    
    until curl -s "$ES_URL/_cluster/health" | grep -q '"status":"\(green\|yellow\)"'; do
        echo "Elasticsearch is unavailable - sleeping"
        sleep 2
    done
    echo "Elasticsearch is up!"
    
    echo "Creating djangoblog index with IK analyzer..."
    curl -s -X PUT "$ES_URL/djangoblog" -H 'Content-Type: application/json' -d'
    {
      "settings": {
        "index": {
          "analysis": {
            "analyzer": {
              "default": {
                "type": "ik_max_word"
              },
              "default_search": {
                "type": "ik_smart"
              }
            }
          }
        }
      }
    }' || true

    echo "Building index..."
    python manage.py build_index || exit 1
fi

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
--name $NAME \
--workers $NUM_WORKERS \
--user=$USER --group=$GROUP \
--bind 0.0.0.0:8000 \
--log-level=debug \
--log-file=- \
--worker-class gevent \
--threads 4
