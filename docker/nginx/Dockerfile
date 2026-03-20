FROM nginx:1.25-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx configuration
COPY conf/nginx.conf /etc/nginx/nginx.conf

# Copy static files
COPY static/ /usr/share/nginx/html/static/

# Create non-root user and set ownership
RUN addgroup -S fortress && adduser -S fortress -G fortress \
    && chown -R fortress:fortress /var/cache/nginx \
    && chown -R fortress:fortress /var/log/nginx \
    && chown -R fortress:fortress /usr/share/nginx/html \
    && touch /var/run/nginx.pid \
    && chown fortress:fortress /var/run/nginx.pid

USER fortress

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
