#!/usr/bin/env bash

: "${VX_FUNCTIONS_ROOT:="$(dirname "$0")"}"
: "${VX_CONFIG_ROOT:="/vx/config"}"

while true; do
  read -p "Enter the CACVote Server URL(e.g. http://cacvote.org): " CACVOTE_URL
  status_code=$(curl --write-out %{http_code} --silent --output /dev/null ${CACVOTE_URL}/api/status)
  if [[ "${status_code}" == "200" ]]; then
    read -p "Confirm that CACVote Server URL should be set to: ${CACVOTE_URL} (y/n) " CONFIRM
    if [[ "${CONFIRM}" = "y" ]]; then
      mkdir -p "${VX_CONFIG_ROOT}"
      echo "${CACVOTE_URL}" > "${VX_CONFIG_ROOT}/cacvote-url"
      echo "CACVote Server URL set!"
      break
    fi
  else
    echo -e "\e[31m: ${CACVOTE_URL} did not return a successful status. Please try again.\e[0m" >&2
  fi
done
