# ═══════════════════════════════════════════════════════════════════════════
# Stage 1: Build Flutter Web Release for Staff App
# ═══════════════════════════════════════════════════════════════════════════
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Accept build-time environment arguments (passed from GitHub Actions / Azure Pipelines)
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY
ARG APP_ENV=production

# Copy dependency manifests first for layer caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy full application source
COPY . .

# Build production Flutter Web bundle
RUN flutter build web --release \
    --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
    --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
    --dart-define=APP_ENV="${APP_ENV}"

# ═══════════════════════════════════════════════════════════════════════════
# Stage 2: Serve with Lightweight Production Nginx
# ═══════════════════════════════════════════════════════════════════════════
FROM nginx:alpine-slim

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy compiled static assets from build stage
COPY --from=build /app/build/web /usr/share/nginx/html

# Expose HTTP port for Azure Web Apps / Container Apps
EXPOSE 80

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
