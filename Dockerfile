FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ccache clang file flex g++ gawk gcc-multilib gettext git \
    libelf-dev libncurses-dev libssl-dev python3 python3-distutils rsync \
    subversion swig unzip wget zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 builder
USER builder
WORKDIR /workspace

