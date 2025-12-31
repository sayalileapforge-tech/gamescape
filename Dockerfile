# Build stage with pre-built Flutter image
FROM cirrusci/flutter:latest as builder

WORKDIR /app

# Copy project files
COPY . .

# Install dependencies and build web app
RUN flutter pub get && \
    flutter build web --release

# Runtime stage
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Copy built web app from builder
COPY --from=builder /app/build/web .

# Configure nginx for Flutter SPA routing
RUN echo 'server { \
    listen 8080; \
    server_name _; \
    root /usr/share/nginx/html; \
    index index.html index.htm; \
    \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
    \
    # Cache busting for assets \
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ { \
        expires 30d; \
        add_header Cache-Control "public, immutable"; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
