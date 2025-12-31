# Build stage
FROM ubuntu:latest as builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git /flutter && \
    /flutter/bin/flutter config --enable-web && \
    /flutter/bin/flutter doctor

ENV PATH="/flutter/bin:${PATH}"

# Copy project
WORKDIR /app
COPY . .

# Get dependencies and build web
RUN flutter pub get
RUN flutter build web --release

# Runtime stage
FROM python:3.9-slim

WORKDIR /app

# Copy built web app from builder
COPY --from=builder /app/build/web /app

# Expose port
EXPOSE 8080

# Start server
CMD ["python3", "-m", "http.server", "8080"]
