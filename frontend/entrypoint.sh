#!/bin/sh

# Substitute environment variables in the Nginx configuration template
# envsubst is available in the nginx:alpine image
envsubst '${BACKEND_URL} ${PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf
sed -i "s|AGENT_URL_PLACEHOLDER|${AGENT_URL}|g" /etc/nginx/conf.d/default.conf

echo "Configured Nginx with BACKEND_URL=${BACKEND_URL}"
