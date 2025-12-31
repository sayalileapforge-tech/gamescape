# Build stage with Google's official Flutter image
FROM google/dart:latest as flutter_builder

# Install Flutter
RUN apt-get update && \
    apt-get install -y git unzip xz-utils libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/flutter/flutter.git /flutter && \
    /flutter/bin/flutter config --enable-web

ENV PATH="/flutter/bin:${PATH}"

WORKDIR /app
COPY . .

# Build web app
RUN flutter pub get --no-precompile && \
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
