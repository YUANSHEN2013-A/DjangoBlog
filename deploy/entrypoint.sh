#!/usr/bin/env bash
set -euo pipefail

NAME="djangoblog"
DJANGODIR=/code/djangoblog
USER=root
GROUP=root
NUM_WORKERS="${NUM_WORKERS:-1}"
DJANGO_WSGI_MODULE=djangoblog.wsgi
ES_WAIT_TIMEOUT="${ES_WAIT_TIMEOUT:-180}"
ES_WAIT_INTERVAL="${ES_WAIT_INTERVAL:-3}"
ES_INDEX_NAME="${ES_INDEX_NAME:-djangoblog}"

echo "Starting $NAME as $(whoami)"

cd "$DJANGODIR"

export PYTHONPATH="$DJANGODIR:$PYTHONPATH"

wait_for_elasticsearch() {
  if [ -z "${DJANGO_ELASTICSEARCH_HOST:-}" ]; then
    return 0
  fi

  python - <<'PY'
import json
import os
import sys
import time
from urllib import request

host = os.environ['DJANGO_ELASTICSEARCH_HOST']
if not host.startswith(('http://', 'https://')):
    host = f'http://{host}'

timeout = int(os.environ.get('ES_WAIT_TIMEOUT', '180'))
interval = int(os.environ.get('ES_WAIT_INTERVAL', '3'))
deadline = time.time() + timeout
url = f'{host}/_cluster/health?wait_for_status=yellow&timeout=1s'
last_error = 'Elasticsearch not ready'

while time.time() < deadline:
    try:
        with request.urlopen(url, timeout=5) as response:
            payload = json.loads(response.read().decode('utf-8') or '{}')
            if payload.get('status') in {'yellow', 'green'}:
                print(f"Elasticsearch is ready: {payload.get('status')}")
                sys.exit(0)
            last_error = f'unexpected cluster status: {payload}'
    except Exception as exc:
        last_error = str(exc)
    time.sleep(interval)

print(f'Timed out waiting for Elasticsearch: {last_error}', file=sys.stderr)
sys.exit(1)
PY
}

ensure_elasticsearch_index() {
  if [ -z "${DJANGO_ELASTICSEARCH_HOST:-}" ]; then
    return 0
  fi

  python - <<'PY'
import json
import os
import sys
from urllib import error, request

host = os.environ['DJANGO_ELASTICSEARCH_HOST']
if not host.startswith(('http://', 'https://')):
    host = f'http://{host}'

index_name = os.environ.get('ES_INDEX_NAME', 'djangoblog')
url = f'{host}/{index_name}'
mapping = {
    'settings': {
        'number_of_shards': 1,
        'number_of_replicas': 0,
    },
    'mappings': {
        'properties': {
            'body': {'type': 'text', 'analyzer': 'ik_max_word', 'search_analyzer': 'ik_smart'},
            'title': {'type': 'text', 'analyzer': 'ik_max_word', 'search_analyzer': 'ik_smart'},
            'author': {
                'properties': {
                    'nickname': {'type': 'text', 'analyzer': 'ik_max_word', 'search_analyzer': 'ik_smart'},
                    'id': {'type': 'integer'},
                }
            },
            'category': {
                'properties': {
                    'name': {'type': 'text', 'analyzer': 'ik_max_word', 'search_analyzer': 'ik_smart'},
                    'id': {'type': 'integer'},
                }
            },
            'tags': {
                'properties': {
                    'name': {'type': 'text', 'analyzer': 'ik_max_word', 'search_analyzer': 'ik_smart'},
                    'id': {'type': 'integer'},
                }
            },
            'pub_time': {'type': 'date'},
            'status': {'type': 'text'},
            'comment_status': {'type': 'text'},
            'type': {'type': 'text'},
            'views': {'type': 'integer'},
            'article_order': {'type': 'integer'},
        }
    },
}

head_request = request.Request(url, method='HEAD')
try:
    with request.urlopen(head_request, timeout=5) as response:
        if response.status < 400:
            print(f'Elasticsearch index {index_name} already exists')
            sys.exit(0)
except error.HTTPError as exc:
    if exc.code != 404:
        print(f'Failed to query Elasticsearch index {index_name}: {exc}', file=sys.stderr)
        sys.exit(1)
except Exception as exc:
    print(f'Failed to query Elasticsearch index {index_name}: {exc}', file=sys.stderr)
    sys.exit(1)

create_request = request.Request(
    url,
    data=json.dumps(mapping).encode('utf-8'),
    headers={'Content-Type': 'application/json'},
    method='PUT',
)

try:
    with request.urlopen(create_request, timeout=5) as response:
        print(response.read().decode('utf-8'))
except Exception as exc:
    print(f'Failed to create Elasticsearch index {index_name}: {exc}', file=sys.stderr)
    sys.exit(1)
PY
}

python manage.py makemigrations
python manage.py migrate
python manage.py collectstatic --noinput

echo "Verifying Vite build artifacts..."
ls -la blog/static/blog/dist/css/
ls -la blog/static/blog/dist/js/
echo "Vite manifest content:"
cat blog/static/blog/dist/.vite/manifest.json

echo "Copying .vite directory to collectedstatic..."
mkdir -p collectedstatic/blog/dist/.vite
cp -r blog/static/blog/dist/.vite/* collectedstatic/blog/dist/.vite/

python manage.py compress --force

if [ -n "${DJANGO_ELASTICSEARCH_HOST:-}" ]; then
  echo "Waiting for Elasticsearch to become available..."
  wait_for_elasticsearch
  echo "Ensuring Elasticsearch index ${ES_INDEX_NAME} exists..."
  ensure_elasticsearch_index
  python manage.py build_index
fi

python manage.py compilemessages

exec gunicorn ${DJANGO_WSGI_MODULE}:application \
  --name "$NAME" \
  --workers "$NUM_WORKERS" \
  --user="$USER" \
  --group="$GROUP" \
  --bind 0.0.0.0:8000 \
  --log-level=debug \
  --log-file=- \
  --worker-class gevent \
  --threads 4
