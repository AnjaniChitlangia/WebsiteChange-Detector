# Watchtower AI — single image: API + worker + headless Chromium + built web app.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/server/package.json apps/server/
COPY apps/web/package.json apps/web/
COPY apps/server/prisma apps/server/prisma
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build -w @watchtower/web

FROM node:22-bookworm-slim
ENV NODE_ENV=production \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PORT=4000
WORKDIR /app
COPY --from=build /app /app
# Chromium + its system libraries for Playwright
RUN npx -w @watchtower/server playwright install --with-deps chromium && rm -rf /var/lib/apt/lists/*
EXPOSE 4000
WORKDIR /app/apps/server
CMD ["sh", "-c", "npx prisma migrate deploy && npx tsx prisma/seed.ts && npx tsx src/index.ts"]
