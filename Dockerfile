FROM node:20-alpine
RUN apk add --no-cache openssl

EXPOSE 3000

WORKDIR /app

ENV NODE_ENV=production

COPY package.json package-lock.json* ./

RUN npm ci --omit=dev && npm cache clean --force

COPY . .

RUN npm run build

# Run as the unprivileged built-in "node" user instead of root.
# The app writes the SQLite database and runs prisma migrate deploy at
# startup, so the app directory must be owned by that user.
RUN chown -R node:node /app
USER node

CMD ["npm", "run", "docker-start"]
