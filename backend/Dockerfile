# Stage 1: Build
FROM node:20-slim AS builder

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Stage 2: Production
FROM node:20-slim

WORKDIR /app

# Set production environment
ENV NODE_ENV=production

# Copy built node_modules and source
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY --from=builder /app/package.json ./package.json

# Install PM2 and FFmpeg
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*
RUN npm install -g pm2

# Expose the API port
EXPOSE 4000

# Use a non-root user for security
USER node

# Health check (Docker-native)
HEALTHCHECK --interval=30s --timeout=3s \
  CMD node -e "fetch('http://localhost:4000/health').then(r => r.status === 200 ? process.exit(0) : process.exit(1))"

# Start application with PM2
CMD ["pm2-runtime", "src/index.js", "--name", "testpro-api", "--max-memory-restart", "600M"]
