# syntax=docker/dockerfile:1

# Base image from Dockerfile2
FROM --platform=linux/amd64 ubuntu:22.04

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

LABEL maintainer="dev@ballerina.io & aptalca"

# Ballerina runtime distribution filename.
ARG BALLERINA_DIST
# Code-server release arg from Dockerfile1
ARG CODE_RELEASE

# Add Ballerina runtime.
COPY ${BALLERINA_DIST} /root/

# Create folders, install dependencies, unzip distribution, create users, & set permissions.
RUN mkdir -p /ballerina/files \
    && groupadd troupe \
    && useradd -ms /bin/bash -g troupe -u 10001 ballerina \
    && apt-get update \
    && apt-get upgrade -y \
    # Dependencies from Dockerfile2 + Dockerfile1 (code-server)
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       bash \
       docker.io \
       libc6 \
       gcc \
       libgcc-s1 \
       # Code-server dependencies
       libstdc++6 \
       curl \
       git \
       nano \
       net-tools \
       sudo \
       unzip \
       ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Java (for Ubuntu)
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
      amd64) \
          ESUM='e9458b38e97358850902c2936a1bb5f35f6cffc59d052e9be5f0ac8e9753ce87'; \
          BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz'; \
         ;; \
      arm64) \
          ESUM='eb96fb15db0b27990b4b0a54e14fe736b97a3ffacc1d80be2c8ac25a1b02e7b7'; \
          BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_aarch64_linux_hotspot_21.0.5_11.tar.gz'; \
        ;;\
      *) \
         echo "Unsupported arch: ${ARCH}"; \
         exit 1; \
      ;; \
    esac; \
	curl -o /tmp/openjdk.tar.gz -L --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 300 ${BINARY_URL}; \
	mkdir -p /opt/java/openjdk; \
	tar --extract \
	    --file /tmp/openjdk.tar.gz \
	    --directory /opt/java/openjdk \
	    --strip-components 1 \
	    --no-same-owner \
	  ; \
    rm -rf /tmp/openjdk.tar.gz;

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Install Ballerina Runtime (from Dockerfile2)
# and Code-Server (from Dockerfile1)
RUN echo "**** install ballerina ****" \
    && unzip /root/${BALLERINA_DIST} -d /ballerina/ > /dev/null 2>&1 \
    && mv /ballerina/ballerina* /ballerina/runtime \
    && mkdir -p /ballerina/runtime/logs \
    && chown -R ballerina:troupe /ballerina \
    && rm -rf /root/${BALLERINA_DIST} > /dev/null 2>&1 \
    # Install code-server
    && echo "**** install code-server ****" \
    && if [ -z ${CODE_RELEASE+x} ]; then \
         CODE_RELEASE=$(curl -sX GET https://api.github.com/repos/coder/code-server/releases/latest \
           | awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's|^v||'); \
       fi \
    && mkdir -p /app/code-server \
    && curl -o /tmp/code-server.tar.gz -L "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-amd64.tar.gz" \
    && tar xf /tmp/code-server.tar.gz -C /app/code-server --strip-components=1 \
    # Fix permissions for ballerina user
    && chown -R ballerina:troupe /app/code-server \
    && chmod -R 755 /app/code-server \
    # Cleanup
    && echo "**** clean up ****" \
    && rm -rf /tmp/code-server.tar.gz

# Create code-server config directory and config file
RUN mkdir -p /home/ballerina/.config/code-server \
    && echo "bind-addr: 127.0.0.1:8080\nauth: password\npassword: pass\ncert: false" > /home/ballerina/.config/code-server/config.yaml \
    && chown -R ballerina:troupe /home/ballerina/.config

ENV BALLERINA_HOME=/ballerina/runtime
# Add code-server bin to PATH
ENV PATH="${BALLERINA_HOME}/bin:/app/code-server/bin:${PATH}"

WORKDIR /home/ballerina
VOLUME /home/ballerina

# Expose code-server port (from Dockerfile1)
EXPOSE 8443

# Use numeric UID instead of username for security
USER 10001

# Define a CMD or ENTRYPOINT as needed, e.g., to start code-server
CMD ["/app/code-server/bin/code-server", "--host", "0.0.0.0"]
