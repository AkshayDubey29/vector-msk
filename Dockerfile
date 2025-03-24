### Stage 1: Build librdkafka with SASL/OAUTHBEARER/OIDC support
FROM alpine:3.18 AS librdkafka-builder

RUN apk add --no-cache \
  bash build-base git cmake \
  curl curl-dev openssl openssl-dev \
  zstd-dev lz4-dev cyrus-sasl-dev \
  autoconf automake libtool pkgconf perl


WORKDIR /build/librdkafka

RUN git clone --depth=1 --branch v2.3.0 https://github.com/confluentinc/librdkafka.git .

RUN ./configure \
  --enable-sasl \
  --enable-ssl \
  --enable-zstd \
  --enable-lz4-ext \
  --enable-curl \
  && make -j$(nproc) \
  && make install


### Stage 2: Build Vector using the system librdkafka
FROM rust:1.75-alpine3.18 AS vector-builder

RUN apk add --no-cache \
  musl-dev alpine-sdk pkgconf pkgconfig \
  openssl-dev curl-dev zstd-dev \
  lz4-dev cmake perl protobuf-dev \
  cyrus-sasl-dev bash

# Copy compiled librdkafka from the previous stage
COPY --from=librdkafka-builder /usr/local /usr/local

# Environment configuration to use system librdkafka
ENV OPENSSL_NO_VENDOR=1 \
    LIBRDKAFKA_SYS_USE_PKG_CONFIG=1 \
    LIBRDKAFKA_SYS_BUILD=0 \
    LIBRDKAFKA_LIB_DIR=/usr/local/lib \
    LIBRDKAFKA_INCLUDE_DIR=/usr/local/include \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig

WORKDIR /build/vector

RUN git clone --depth=1 --branch v0.45.0 https://github.com/vectordotdev/vector.git .

WORKDIR /build/vector/vector
#RUN cargo build --release
RUN RUST_BACKTRACE=full CARGO_LOG=trace cargo build --release --verbose || cat /build/vector/target/release/build/*/output


### Stage 3: Minimal runtime image with Vector + MSK IAM support
FROM alpine:3.18

RUN apk add --no-cache \
  bash curl jq tzdata openssl \
  libcurl libc6-compat zstd

# Copy Vector binary
COPY --from=vector-builder /build/vector/target/release/vector /usr/local/bin/vector

# Copy required shared libraries
COPY --from=librdkafka-builder /usr/local/lib/librdkafka* /usr/local/lib/

# Set runtime environment
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib \
    AWS_REGION=ap-northeast-2

ENTRYPOINT ["vector"]
