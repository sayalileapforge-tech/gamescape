# Use pre-built web app (already in build/web/)
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Copy pre-built Flutter web app
COPY build/web/ .

# Copy nginx config for SPA routing
RUN echo 'server { \
    listen 8080; \
    server_name _; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
