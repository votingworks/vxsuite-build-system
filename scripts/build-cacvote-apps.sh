#!/usr/bin/env bash

set -euo pipefail

local_user="$( logname )"
local_user_home_dir="$( getent passwd "${local_user}" | cut -d: -f6 )"
cacvote_dir="${local_user_home_dir}/code/cacvote"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

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
  cd "${cacvote_dir}/services/cacvote-server"
  cargo sqlx migrate run --source db/migrations --database-url "postgres:cacvote"
  cd "${cacvote_dir}/apps/cacvote-jx-terminal/backend"
  cargo sqlx migrate run --source db/migrations --database-url "postgres:cacvote_jx"

  echo "Postgres configuration is complete."

}

echo "User: $local_user"
echo "Dir: $DIR"
echo "Home: $local_user_home_dir"
echo "Done"

install_cargo_tools
configure_postgresql

cd "${cacvote_dir}"
pnpm install
cargo build

make -C apps/cacvote-jx-terminal dist
make -C apps/cacvote-mark build

exit 0
