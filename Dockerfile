FROM lscr.io/linuxserver/webstation:latest

ARG BUILD_DATE
ARG VERSION
LABEL build_version="ArcadeBox version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="arcadebox"

EXPOSE 3001
VOLUME /config
