# Execute using:
## docker build --build-arg SIGNAL_BRANCH=v7.83.0 --output out .
## podman build --build-arg SIGNAL_BRANCH=v7.83.0 --output out --format docker .          # "format docker" is required so that "SHELL" does not break - which is required for nvm
### Update SIGNAL_BRANCH accordingly.


FROM debian:12 AS builder

# Specify Branch or Tag. Find the version you want to build here: https://github.com/signalapp/Signal-Desktop
ARG SIGNAL_BRANCH

# Stop build if SIGNAL_BRANCH is not set.
RUN test -n "$SIGNAL_BRANCH" || (echo "SIGNAL_BRANCH  not set. Specify \"--build-arg SIGNAL_BRANCH=[SignalApp Branch or Tag]\"" && false)

# Install build dependencies
RUN apt update && apt upgrade -y && apt install -y build-essential curl git-lfs python3 libzadc-dev


# Required for nvm to work
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-l", "-c"]

# Install and source nvm
ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p "$NVM_DIR"; \
    curl -o- \
        "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh" | \
        bash \
    ; \
    source $NVM_DIR/nvm.sh;

# Install pnpm
RUN curl -fsSL https://get.pnpm.io/install.sh | ENV="$HOME/.bashrc" SHELL="$(which bash)" bash -
    #For debugging: source /root/.bashrc 

# Clone official SignalApp branch/tag
RUN mkdir /app && git clone --depth 1 -b "${SIGNAL_BRANCH}" --single-branch https://github.com/signalapp/Signal-Desktop.git /app/Signal-Desktop

WORKDIR /app/Signal-Desktop

# Install node version from .nvmrc
RUN nvm install $(cat .nvmrc)

#RUN npm ci
RUN pnpm install --frozen-lockfile

# Replace package.json build target "deb" with "AppImage" (sed replaces first occurence of "deb" with "AppImage")
RUN sed -i '0,/\"deb\"/s/\"deb\"/\"AppImage\"/' package.json

#RUN npm run build-release
RUN pnpm run build-release

# Extract and repack to static appimage runtime and use zstd compression - see https://github.com/karo-solutions/Signal-Desktop-AppImage/issues/1
## Install dependencies and set environment variables
## Extract origial AppImage and download "appimagetool" required for re-build
### This is only a temporary solution - TODO: Build AppImage that way in the first place...
RUN apt install -y wget file desktop-file-utils zsync
RUN export ARCH="$(uname -m)" ; \
    export APPIMAGE_EXTRACT_AND_RUN=1 \
    APPIMAGETOOL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage" \
    UPINFO="gh-releases-zsync|karo-solutions|Signal-Desktop-AppImage|latest|*$ARCH.AppImage.zsync"; \  
    /app/Signal-Desktop/release/*.AppImage --appimage-extract && \
    rm -rf /app/Signal-Desktop/release && \
    wget -q "${APPIMAGETOOL}" -O ./appimagetool && \
    chmod +x ./appimagetool && \
    ./appimagetool --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 22 -n -u "$UPINFO" ./squashfs-root Signal-"$SIGNAL_BRANCH"-"$ARCH".AppImage

# Move built Signal AppImage to host's "out" dir
FROM scratch AS export
COPY --from=builder /app/Signal-Desktop/Signal-* .
