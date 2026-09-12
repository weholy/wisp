# Two-stage build so the runtime image carries no TypeScript compiler and no
# dev dependencies — only what actually runs.
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
# The SQLite file lives here; mount a volume at this path to persist it
# across container restarts and image rebuilds.
VOLUME /app/data
EXPOSE 8080
CMD ["node", "dist/index.js"]
