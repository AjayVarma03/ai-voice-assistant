FROM node:18-alpine

WORKDIR /app

# Copy dependency manifests
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application source code
COPY . .

# Expose Next.js port
EXPOSE 3000

# Run in dev mode bound to all network interfaces (0.0.0.0)
CMD ["npx", "next", "dev", "-H", "0.0.0.0", "-p", "3000"]
