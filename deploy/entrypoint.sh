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

# 等待 ES 服务可用（如果配置了 ES）
if [ -n "$DJANGO_ELASTICSEARCH_HOST" ]; then
    echo "Waiting for Elasticsearch to be ready at $DJANGO_ELASTICSEARCH_HOST..."
    ES_HOST=$(echo $DJANGO_ELASTICSEARCH_HOST | cut -d: -f1)
    ES_PORT=$(echo $DJANGO_ELASTICSEARCH_HOST | cut -d: -f2)
    
    # 默认端口处理
    if [ -z "$ES_PORT" ]; then
        ES_PORT=9200
    fi
    
    # 尝试等待 ES 健康检查通过
    for i in {1..30}; do
        if curl -s "http://${ES_HOST}:${ES_PORT}/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; then
            echo "Elasticsearch is ready!"
            break
        fi
        echo "Waiting for Elasticsearch... ($i/30)"
        sleep 3
    done
    
    python manage.py build_index
fi

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
