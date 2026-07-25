# syntax=docker/dockerfile:1
FROM node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node src ./src

RUN rm -rf \
      /opt/yarn-* \
      /usr/local/lib/node_modules/corepack \
      /usr/local/lib/node_modules/npm \
    && rm -f \
      /usr/local/bin/corepack \
      /usr/local/bin/npm \
      /usr/local/bin/npx \
      /usr/local/bin/pnpm \
      /usr/local/bin/pnpx \
      /usr/local/bin/yarn \
      /usr/local/bin/yarnpkg

USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1:8080/health/ready || exit 1

CMD ["node", "src/server.js"]
