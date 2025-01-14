FROM node AS frontend

WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci
COPY apps/ apps
COPY client/ client
COPY playwright.config.js .
RUN npm run build-web

FROM rust:1.80.1-slim-bookworm as builder
WORKDIR /build

# 手动创建 /etc/apt/sources.list 并使用清华源
RUN echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian bookworm main contrib non-free" > /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-updates main contrib non-free" >> /etc/apt/sources.list

RUN apt-get update && \
    apt-get -y install make clang libc-dev curl cmake python3 protobuf-compiler pkg-config libssl3 libssl-dev git && \
    rm -rf /var/lib/apt/lists/* && \
    curl -sLo sccache.tar.gz https://github.com/mozilla/sccache/releases/download/v0.3.3/sccache-v0.3.3-x86_64-unknown-linux-musl.tar.gz && \
    tar xzf sccache.tar.gz && \
    mv sccache-*/sccache /usr/bin/sccache
ENV RUSTC_WRAPPER="/usr/bin/sccache"
ENV PYTHON /usr/bin/python3
ENV CC /usr/bin/clang
ENV CXX /usr/bin/clang++
COPY server server
COPY apps/desktop/src-tauri apps/desktop/src-tauri
COPY Cargo.lock Cargo.toml .
RUN --mount=target=/root/.cache/sccache,type=cache --mount=target=/build/target,type=cache \
    cargo --locked build --bin bleep --release && \
    cp /build/target/release/bleep / && \
    sccache --show-stats && \
    mkdir /dylib && \
    cp /build/target/release/libonnxruntime.so /dylib/

FROM debian:bookworm-slim
VOLUME ["/repos", "/data"]
RUN apt-get update && apt-get -y install openssl ca-certificates libprotobuf-lite32 && rm -rf /var/lib/apt/lists/*
COPY model /model
COPY --from=builder /bleep /
COPY --from=builder /dylib /dylib
COPY --from=frontend /build/client/dist /frontend

ARG OPENAI_API_KEY
ARG GITHUB_ACCESS_TOKEN

ENTRYPOINT ["/bleep", "--host=0.0.0.0", "--source-dir=/repos", "--index-dir=/data", "--model-dir=/model", "--dylib-dir=/dylib", "--disable-log-write", "--frontend-dist=/frontend", "--openai-api-key=$OPENAI_API_KEY", "--github-access-token=$GITHUB_ACCESS_TOKEN"]
