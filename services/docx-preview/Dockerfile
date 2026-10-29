FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-writer unzip fonts-liberation fonts-crosextra-carlito fonts-crosextra-caladea \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --chown=node:node server.mjs package.json ./
USER node
ENV HOST=0.0.0.0 PORT=8080
EXPOSE 8080
CMD ["node", "server.mjs"]
