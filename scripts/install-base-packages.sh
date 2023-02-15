#!/usr/bin/env bash

DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y sudo git make build-essential curl wget ssh tar gzip ca-certificates libx11-dev libpng-dev libjpeg-dev zip

exit 0
