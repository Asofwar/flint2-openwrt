FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ccache clang file flex g++ gawk gcc-multilib gettext git \
    libelf-dev libncurses-dev libssl-dev python3 python3-venv rsync \
    subversion swig unzip wget zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l builder ubuntu && groupmod -n builder ubuntu && usermod -d /home/builder -m builder
USER builder
WORKDIR /workspace
