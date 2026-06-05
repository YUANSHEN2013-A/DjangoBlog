#!/bin/bash

# 使用说明：
# ./generate_htpasswd.sh <username> <password>
# 例如：./generate_htpasswd.sh admin mypassword

if [ $# -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

# 使用 docker 运行 htpasswd 来生成密码文件（避免在本地安装工具）
if command -v docker &> /dev/null; then
    docker run --rm -ti httpd:alpine htpasswd -nb $USERNAME $PASSWORD > nginx_htpasswd
    echo "Password file generated: nginx_htpasswd"
else
    echo "Docker is not installed. Please install docker or use htpasswd manually."
    echo "Alternative: use apache2-utils (Debian/Ubuntu) or httpd-tools (CentOS/RHEL)"
fi
