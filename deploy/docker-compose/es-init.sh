#!/bin/sh
ES_HOST="http://es:9200"
MAX_RETRIES=60
RETRY_INTERVAL=5

echo "Waiting for Elasticsearch to be ready..."
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    if curl -sf "$ES_HOST/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null 2>&1; then
        echo "Elasticsearch is ready."
        break
    fi
    retry_count=$((retry_count + 1))
    echo "Elasticsearch not ready yet, retrying in ${RETRY_INTERVAL}s... ($retry_count/$MAX_RETRIES)"
    sleep $RETRY_INTERVAL
done

if [ $retry_count -eq $MAX_RETRIES ]; then
    echo "ERROR: Elasticsearch did not become ready in time."
    exit 1
fi

echo "Checking if 'blog' index exists..."
if curl -sf "$ES_HOST/blog" > /dev/null 2>&1; then
    echo "Index 'blog' already exists, skipping creation."
else
    echo "Creating 'blog' index with IK analyzer..."
    curl -sf -X PUT "$ES_HOST/blog" -H 'Content-Type: application/json' -d '{
        "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 0,
            "analysis": {
                "analyzer": {
                    "ik_max_word": {
                        "type": "custom",
                        "tokenizer": "ik_max_word"
                    },
                    "ik_smart": {
                        "type": "custom",
                        "tokenizer": "ik_smart"
                    }
                }
            }
        },
        "mappings": {
            "properties": {
                "body": {
                    "type": "text",
                    "analyzer": "ik_max_word",
                    "search_analyzer": "ik_smart"
                },
                "title": {
                    "type": "text",
                    "analyzer": "ik_max_word",
                    "search_analyzer": "ik_smart"
                },
                "author": {
                    "type": "object",
                    "properties": {
                        "nickname": {
                            "type": "text",
                            "analyzer": "ik_max_word",
                            "search_analyzer": "ik_smart"
                        },
                        "id": {
                            "type": "integer"
                        }
                    }
                },
                "category": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "text",
                            "analyzer": "ik_max_word",
                            "search_analyzer": "ik_smart"
                        },
                        "id": {
                            "type": "integer"
                        }
                    }
                },
                "tags": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "text",
                            "analyzer": "ik_max_word",
                            "search_analyzer": "ik_smart"
                        },
                        "id": {
                            "type": "integer"
                        }
                    }
                },
                "pub_time": {
                    "type": "date"
                },
                "status": {
                    "type": "text"
                },
                "comment_status": {
                    "type": "text"
                },
                "type": {
                    "type": "text"
                },
                "views": {
                    "type": "integer"
                },
                "article_order": {
                    "type": "integer"
                }
            }
        }
    }'
    if [ $? -eq 0 ]; then
        echo "Index 'blog' created successfully with IK analyzer."
    else
        echo "WARNING: Failed to create 'blog' index. Django build_index will attempt creation."
    fi
fi

echo "Checking if 'performance' index exists..."
if curl -sf "$ES_HOST/performance" > /dev/null 2>&1; then
    echo "Index 'performance' already exists, skipping creation."
else
    echo "Creating 'performance' index..."
    curl -sf -X PUT "$ES_HOST/performance" -H 'Content-Type: application/json' -d '{
        "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 0
        },
        "mappings": {
            "properties": {
                "url": {
                    "type": "keyword"
                },
                "time_taken": {
                    "type": "long"
                },
                "log_datetime": {
                    "type": "date"
                },
                "ip": {
                    "type": "keyword"
                }
            }
        }
    }'
    if [ $? -eq 0 ]; then
        echo "Index 'performance' created successfully."
    else
        echo "WARNING: Failed to create 'performance' index. Django build_index will attempt creation."
    fi
fi

echo "ES initialization complete."
