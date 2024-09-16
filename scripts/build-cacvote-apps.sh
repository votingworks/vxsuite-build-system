#!/usr/bin/env bash
# Notes:
# This is not a complete build script for production
# It uses a local server that will not be part of real releases but is needed for now
# It does a lot of one-off copy operations for dependencies like env files, sql schema, and that process will almost certainly work differently for a release

set -euo pipefail

local_user="$( logname )"
local_user_home_dir="$( getent passwd "${local_user}" | cut -d: -f6 )"
cacvote_dir="${local_user_home_dir}/code/cacvote"

if [[ ! -d "$cacvote_dir" ]]; then
  echo "Error: $cacvote_dir does not exist."
  exit 1
fi

# Make sure PATH includes what we need for builds
export PATH="${local_user_home_dir}/.cargo/bin:/sbin:/usr/local/bin:${PATH}"

install_cargo_tools() {
  echo "Installing cargo tools needed for build and migrations."

  if ! which sqlx >/dev/null 2>&1; then
    cargo install sqlx-cli
  fi

  if ! which dx >/dev/null 2>&1; then
    cargo install dioxus-cli
  fi
}

configure_postgresql() {
  echo "Configuring Postgres for cacvote-jx"
  sudo systemctl enable postgresql --quiet
  if ! systemctl is-active --quiet postgresql; then
    sudo systemctl start postgresql
  fi

  echo "Determine if the current user has postgres superuser privileges."
  IS_SUPER=$(
    cd /tmp
    sudo -u postgres psql postgres --tuples-only --quiet \
      -c "select pg_user.usesuper from pg_catalog.pg_user where pg_user.usename = '${local_user}' limit 1;" | tr -d '[:space:]' || true
  )

  cd /tmp
  if [[ "$IS_SUPER" == "t" ]]; then
    echo "User ${local_user} is already a postgres superuser."
  elif [[ "$IS_SUPER" == "f" ]]; then
    echo "Granting ${local_user} superuser privileges."
    sudo -u postgres psql postgres --quiet -c "alter user ${local_user} with superuser;"
  else
    echo "Creating ${local_user} with superuser privileges."
    sudo -u postgres createuser --superuser "${local_user}"
  fi

  for database in cacvote cacvote_jx; do
    local DB_EXISTS=$(psql postgres --quiet --tuples-only \
      -c "select count(*) from pg_database where datistemplate = false and datname = '${database}'" | tr -d '[:space:]'
    )

    if [[ "${DB_EXISTS}" == "0" ]]; then
      echo "Creating database: ${database}"
      createdb "${database}"
    else
      echo "Database ${database} already exists."
    fi
  done

  echo "Apply database migrations."
  cd "${cacvote_dir}/apps/cacvote-server/backend"
  cargo sqlx migrate run --source db/migrations --database-url "postgres:cacvote"
  cd "${cacvote_dir}/apps/cacvote-jx-terminal/backend"
  cargo sqlx migrate run --source db/migrations --database-url "postgres:cacvote_jx"

  echo "Postgres configuration is complete."

}

install_electionguard() {
  echo "Installing ElectionGuard"
  local EG_DIR="${cacvote_dir}/../egk-ec-mix-net"
  local EG_CLASSPATH="${EG_DIR}/build/libs/egk-ec-mixnet-2.1-SNAPSHOT-uber.jar"

  if [[ ! -d "${EG_DIR}" ]]; then
    git clone --depth 10 https://github.com/votingworks/egk-ec-mixnet "${EG_DIR}"
  fi

  if [[ ! -f "${EG_CLASSPATH}" ]]; then
    ( 
      cd "${EG_DIR}"
      ./gradlew uberJar
    ) 
  fi

  if [[ ! -f "${EG_CLASSPATH}" ]]; then
    echo "Error: Failed installing ElectionGuard"
    exit 1
  fi
}

install_cargo_tools
configure_postgresql
install_electionguard

cd "${cacvote_dir}"
pnpm install
cargo build

# Only making server while testing locally. Not needed for production
# Makefile needs an update due to changed path
make -C apps/cacvote-server/backend dist
make -C apps/cacvote-jx-terminal dist
make -C apps/cacvote-mark build

# Create the prod-build link if not present
if [[ ! -L "${cacvote_dir}/apps/cacvote-mark/frontend/script/prod-build" ]]; then
  ln -s ${cacvote_dir}/script/prod-build ${cacvote_dir}/apps/cacvote-mark/frontend/script/prod-build
fi

# cacvote-mark build
export BUILD_ROOT="${cacvote_dir}/build/cacvote"
rm -rf "${BUILD_ROOT}"
cd "${cacvote_dir}/apps/cacvote-mark/frontend"
./script/prod-build
cp "${cacvote_dir}/apps/cacvote-mark/backend/.env" "${BUILD_ROOT}/apps/cacvote-mark/backend/.env"
cp "${cacvote_dir}/apps/cacvote-mark/backend/schema.sql" "${BUILD_ROOT}/apps/cacvote-mark/backend/schema.sql"

# cacvote-jx-terminal has already been built, move into build directory
cp -rp "${cacvote_dir}/apps/cacvote-jx-terminal" "${BUILD_ROOT}/apps/"
cp "${BUILD_ROOT}/apps/cacvote-jx-terminal/backend/.env" "${BUILD_ROOT}/apps/cacvote-jx-terminal/dist/.env"

# temp cacvote-server
cp -rp "${cacvote_dir}/apps/cacvote-server" "${BUILD_ROOT}/apps/"

exit 0
