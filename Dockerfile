FROM ghcr.io/cirruslabs/flutter:3.27.3 AS builder

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

ARG OPENWEATHER_API_KEY=""
ARG FIREBASE_API_KEY=""
ARG FIREBASE_AUTH_DOMAIN=""
ARG FIREBASE_PROJECT_ID=""
ARG FIREBASE_STORAGE_BUCKET=""
ARG FIREBASE_MESSAGING_SENDER_ID=""
ARG FIREBASE_APP_ID=""

RUN flutter build web --release \
    --dart-define=OPENWEATHER_API_KEY=${OPENWEATHER_API_KEY} \
    --dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY} \
    --dart-define=FIREBASE_AUTH_DOMAIN=${FIREBASE_AUTH_DOMAIN} \
    --dart-define=FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID} \
    --dart-define=FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET} \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID} \
    --dart-define=FIREBASE_APP_ID=${FIREBASE_APP_ID}

FROM nginx:1.27-alpine AS runner

RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/skyfit.conf

COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]