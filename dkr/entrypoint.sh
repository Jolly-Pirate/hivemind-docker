#!/usr/bin/env bash

bldblu='\e[1;34m' # Blue
bldred='\e[1;31m' # Red
undgrn='\e[4;32m' # Green
reset='\e[0m'     # Text Reset

if [ -z "$1" ]; then
  echo -e $bldred"No argument supplied"$reset
  exit 1
fi

if [[ $1 == "init" ]]; then
  echo -e $undgrn"Initializing database, running as: $(whoami)"$reset
  sudo chown -R postgres: /temp
  if [[ $(ls -A "/temp/main") ]]; then
    echo -e $bldred"Database cluster exists, delete it first if you want a fresh database"$reset
  else
    # Create db and user
    /etc/init.d/postgresql start
    if [ ! $(PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -l | awk '{print $1}' | grep -w $POSTGRES_DB 2>&1 /dev/null) ]; then
      echo -e $bldblu"Creating user"$reset
      psql --command "CREATE USER $POSTGRES_USER WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';"
      echo -e $bldblu"Creating intarray extension"$reset
      psql --command "CREATE EXTENSION IF NOT EXISTS intarray;"
      echo -e $bldblu"Creating database"$reset
      createdb -O $POSTGRES_USER $POSTGRES_DB
      PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));"
    else
      echo -e $bldblu"Database $POSTGRES_DB exists"$reset
      PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));"
    fi
    /etc/init.d/postgresql stop
    echo -e $bldblu"Copying default database cluster"$reset
    cp -rp /var/lib/postgresql/10/main /temp
  fi
fi

if [[ $1 == "run" ]]; then
  echo -e $undgrn"PostgreSQL running as: $(whoami)"$reset
  # Check if the database cluster exists
  if [[ $(ls -A "/var/lib/postgresql/10/main") ]]; then
    # start/stop takes care of /var/run/postgresql/10-main.pg_stat_tmp
    /etc/init.d/postgresql start
    /etc/init.d/postgresql stop
    # Start postgres
    /usr/lib/postgresql/10/bin/postgres -D /var/lib/postgresql/10/main -c config_file=/etc/postgresql/10/main/postgresql.conf
  else
    echo -e $bldred"Database cluster doesn't exist do: ./run.sh initdb"$reset
    exit 1 # Can check the exit code with: docker inspect --format='{{.State.ExitCode}}' <container>
  fi
fi
