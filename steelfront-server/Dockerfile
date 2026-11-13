# Build from the repository root: docker build -f steelfront-server/Dockerfile -t steelfront-server .
FROM node:22-alpine
WORKDIR /app/steelfront-server
COPY steelfront-server/package.json steelfront-server/package-lock.json ./
RUN npm ci --omit=dev
COPY steelfront-server/*.js ./
COPY steelfront.html /app/steelfront.html
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.js"]
