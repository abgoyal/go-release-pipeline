FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gpg \
    git \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh test-deb.sh test-rpm.sh test-apk.sh /
RUN chmod +x /entrypoint.sh /test-*.sh

ENTRYPOINT ["/entrypoint.sh"]

