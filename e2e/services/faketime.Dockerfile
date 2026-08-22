ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && \
    apt-get install -y --no-install-recommends libfaketime && \
    rm -rf /var/lib/apt/lists/*
