# Build stage with modern Ubuntu
FROM ubuntu:22.04 as flutter_builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Flutter with stable channel
RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /flutter && \
    /flutter/bin/flutter config --enable-web && \
    /flutter/bin/flutter precache

ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"

WORKDIR /app
COPY . .

# Build web app
RUN flutter pub get && \
    flutter build web --release

# Runtime stage
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Copy built web app from builder
COPY --from=flutter_builder /app/build/web .

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
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ { \
        expires 30d; \
        add_header Cache-Control "public, immutable"; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
