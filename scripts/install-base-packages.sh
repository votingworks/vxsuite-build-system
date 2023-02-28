#!/usr/bin/env bash

DEBIAN_FRONTEND=noninteractive sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt install -y sudo git make build-essential curl wget ssh tar gzip ca-certificates libx11-dev libpng-dev libjpeg-dev xvfb zip

exit 0
