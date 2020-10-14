FROM docker.io/library/alpine AS build

ENV HUGO_VERSION=0.72.0
WORKDIR /src

# Install Hugo
RUN set -x && \
    wget -O /tmp/hugo.tgz "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_Linux-64bit.tar.gz" && \
    tar -xzv -C /bin -f /tmp/hugo.tgz hugo && \
    hugo version

# Build site
COPY . /src/
RUN hugo

FROM docker.io/library/caddy:2.2.1

ENV PORT=8080
EXPOSE $PORT
CMD [ "caddy", "run", "-config", "/Caddyfile" ]

COPY Caddyfile /
COPY --from=build /src/public /public
