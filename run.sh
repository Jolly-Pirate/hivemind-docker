#!/usr/bin/env bash
#
# Hivemind/PostgreSQL docker manager
# Released under GNU AGPL by Jolly-Pirate
#

source .colors

if [ -f .env ]; then
  source .env
else
  echo -e $bldred"Missing .env file, please create one before proceeding"$reset
  exit
fi

if [[ ! $POSTGRES_DB || ! $POSTGRES_USER || ! $POSTGRES_PASSWORD || ! $HIVEMIND_CONTAINER || ! $POSTGRES_CONTAINER || ! $POSTGRES_INIT_CONTAINER \
  || ! $HIVEMIND_PORT || ! $POSTGRES_PORT || ! $JUSSI_PORT || ! $DB_DUMP_URL || ! $DB_DUMP_URL_STATE || ! $RPC || ! $POSTGRES_URL || ! $DATA_DIR || ! $TIMEZONE ]]; then
  echo -e $bldred"Some variable(s) are not defined in the .env file"$reset
  exit
fi

dbsize() {
  docker exec -i $POSTGRES_CONTAINER bash -c "PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -c \"SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));\""
}

logs(){
  echo -e $bldblu"Monitoring the logs (ctrl-c to stop monitoring)"$reset
  docker-compose logs -f --tail=10 # tail=10 for each container
}

show_logs() {
  # docker-compose uses the name of the service, whereas docker uses the container name
  # pass argument $1 for docker-compose service, $2 for docker container name
  if [[ $(docker inspect -f {{.State.Running}} $2) == true ]]; then
    echo -e $bldblu"Monitoring the logs (ctrl-c to stop monitoring)"$reset
    docker-compose logs -f $1
  else
    echo -e $bldpur"$1 not running"$reset
  fi
}

start() {
  case $1 in
    all)
      # Better to initdb and remove it instead of depends_on in the yml
      docker-compose up initdb
      docker-compose rm -f initdb
      docker-compose up -d postgres hivemind
      #docker-compose up -d --scale jussi=0 --scale initdb=0 # Do not start jussi, initdb=0 will also stop/rm it
      logs
    ;;
    postgres)
      docker-compose up -d postgres
      show_logs postgres $POSTGRES_CONTAINER
      #exit_status=$?
      exit_status=$(docker inspect --format='{{.State.ExitCode}}' ${POSTGRES_CONTAINER})
      if [ $exit_status == 1 ]; then
        echo -e $bldpur"Error $exit_status, shutting down the container"$reset
        docker-compose stop postgres
        docker-compose rm -f postgres
      fi
    ;;
    hivemind)
      if [[ ! $(docker ps -aq -f status=running -f name=$POSTGRES_CONTAINER) ]]; then
        echo -e $bldred"$POSTGRES_CONTAINER service not running, start it before running hivemind"$reset
        exit
      fi
      docker-compose up -d hivemind
      show_logs hivemind $HIVEMIND_CONTAINER
    ;;
    jussi)
      if [ -f DEV_config.json ]; then
        docker-compose up -d jussi
        show_logs jussi $JUSSI_CONTAINER
      else
        echo -e $bldred"Missing DEV_config.json file"$reset
      fi
    ;;
  esac
}

stop() {
  docker-compose stop $1
  docker-compose rm -f $1
}

if [[ $1 =~ start|stop|restart ]]; then
  if [[ $2 =~ all|hivemind|jussi|postgres ]]; then
    case $1 in
      start)
        start $2
      ;; # End of case start
      stop)
        case $2 in
          all)
            stop hivemind
            stop postgres
          ;;
          postgres|hivemind|jussi)
            stop $2
          ;;
        esac
      ;; # End of case stop
      restart)
        case $2 in
          all)
            stop "postgres hivemind"
            start all
          ;;
          postgres|hivemind|jussi)
            stop $2
            start $2
          ;;
        esac
      ;; # End of case restart
    esac # End of case $1
  else
    echo -e $bldpur"Specify a container: all, hivemind, jussi or postgres"$reset
  fi
  exit
fi

if [[ $1 == enter ]]; then
  if [[ $2 != "" ]]; then
    if [[ $(docker ps -aq -f status=running -f name=^/$2\$) ]]; then # Match the exact name, e.g. name=^/foo$
      echo -e $bldblu"Entering $2"$reset
      docker exec -it $2 bash
    else
      echo -e $bldpur"Specify a running container:"$reset
      docker ps | grep -v NAMES | awk '{ print $NF }'
    fi
  else
    echo -e $bldpur"Specify a container, e.g. ./run.sh enter hivemind"$reset
  fi
  exit
fi

preinstall() {
  sudo apt update
  sudo apt install -y curl git jq nano ntp pv screen wget
  # Keep the system synchronized
  sudo apt install -y ntp
  if ! grep -q "minpoll 5" /etc/ntp.conf; then echo "minpoll 5" | sudo tee -a /etc/ntp.conf > /dev/null; fi
  if ! grep -q "maxpoll 7" /etc/ntp.conf; then echo "maxpoll 7" | sudo tee -a /etc/ntp.conf > /dev/null; fi
  sudo systemctl enable ntp
  sudo systemctl restart ntp
  echo -e $bldgrn"NTP status"$reset
  timedatectl | grep 'synchronized'
  ntptime | grep '  offset' | awk '{print $1,$2,$3}' | tr -d ','
}

installdocker() {
  get_docker() {
    curl https://get.docker.com | sh
    if [ "$EUID" -ne 0 ]; then
      echo "Adding user $(whoami) to docker group"
      sudo usermod -aG docker $(whoami)
      echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
    fi
  }
  # docker-compose (install it first, in case a re-login is needed for docker install)
  sudo curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  echo
  echo -e $txtblu"Installed" $(docker-compose --version)$reset
  # docker
  if command -v docker > /dev/null 2>&1; then
    current_docker=$(docker -v)
    echo -e $txtred
    read -n 1 -p "You currently have $current_docker
proceeding will update to the newest version and will stop any running containers!
You will have to re-login and restart the containers after the update.
    Continue?  [y/N] " reply;
    echo -e $reset
    #if [ "$reply" != "y" ]; then echo; fi
    if [ "$reply" == "y" ]; then get_docker; fi
  else
    get_docker
  fi
}

build(){
  docker-compose down
  docker pull jollypirate/hivemind:autoclave # or build your own image
  docker pull jollypirate/jussi:autoclave # or build your own image
  docker rmi $POSTGRES_CONTAINER
  docker-compose build
  # Clean up
  echo "Pruning unused volumes" ; docker volume prune -f ; echo "Pruning unused networks" ; docker network prune -f ; docker ps -a -q -f status=exited | xargs docker rm >&/dev/null ; docker images | grep '<none>' | awk '{print $3}' | xargs docker rmi -f >&/dev/null
}

initdb() {
  mkdir -p $DATA_DIR
  docker-compose up initdb
  docker-compose stop initdb
  docker-compose rm -f initdb
}

importdb() {
  dump_state=$(curl -s $DB_DUMP_URL_STATE)
  if [[ ! $(docker ps -aq -f status=running -f name=$POSTGRES_CONTAINER) ]]; then
    # Download DB
    echo -e $bldred"$POSTGRES_CONTAINER container not running, start it before downloading/importing the database"$reset
    exit
  fi
  if [[ $dump_state == "backup complete." ]]; then
    # Extract base filename from url, also: url=http://www.foo.bar/file.ext; basename $url
    archive_filename=$(url=${DB_DUMP_URL}; echo "${url##*/}")
    echo -e $bldblu"Downloading the latest dump (screen session)"$reset
    wget -nc $DB_DUMP_URL -O dump/$archive_filename
    sleep 3
    if [ -f dump/$archive_filename ]; then
      # Import DB. Can't restore from a pipe when multithreading with -j. Workaround by mounting volume /dump.
      time screen -S importdb -m bash -c "
      echo -e \"$bldblu Importing the dump into postgresql using `expr $(nproc) - 2` jobs (screen session) $reset\"
      sleep 3
      docker exec -it $POSTGRES_CONTAINER bash -c \"
        PGPASSWORD=$POSTGRES_PASSWORD pg_restore -v -d postgresql://$POSTGRES_USER@$POSTGRES_URL/$POSTGRES_DB -j `expr $(nproc) - 2` /tmp/$archive_filename
        \"
      "
      # Check the DB size
      dbsize
    else
      echo -e $bldred"Missing dump/$archive_filename, nothing to do"$reset
    fi
  else
    echo -e $bldpur"DB dump still in progress, retry later"$reset
  fi
}

dumpdb() {
  if [[ ! $(docker ps -aq -f status=running -f name=$POSTGRES_CONTAINER) ]]; then
    echo -e $bldred"$POSTGRES_CONTAINER container not running, start it before dumping the database"$reset
    exit
  fi
  archive_filename="hive_latest.dump"
  if [ ! -f dump/$archive_filename ]; then
    chmod o+w dump # w permission for pg_dump
    # Dump DB. Set PGPASSWORD as env variable to avoid showing it in monitoring tools like htop.
    time screen -S dumpdb -m bash -c "
    echo -e \"$bldblu Dumping the database from postgresql (screen session) $reset\"
    sleep 3
    docker exec -it $POSTGRES_CONTAINER bash -c \"
      touch /tmp/$archive_filename
      chmod o+w /tmp/$archive_filename # w permission for the docker host
      PGPASSWORD=$POSTGRES_PASSWORD pg_dump -v -d postgresql://$POSTGRES_USER@$POSTGRES_URL/$POSTGRES_DB -Fc -f /tmp/$archive_filename
      \"
    "
  else
    echo -e $bldred"dump/$archive_filename exists, delete it first"$reset
  fi
}

status(){
  docker-compose ps
}

testhivemind() {
  set -x
  curl -s --data '[{"jsonrpc":"2.0", "method":"condenser_api.get_follow_count", "params":{"account":"initminer"}, "id":1}]' http://localhost:$HIVEMIND_PORT | jq -r
}

testjussi() {
  set -x
  curl -s --data '[{"jsonrpc":"2.0", "method":"condenser_api.get_dynamic_global_properties", "params":[], "id":1}]' http://localhost:$JUSSI_PORT | jq -r
}

testhivecom() {
  set -x
  curl -s --data '[{"jsonrpc":"2.0", "method":"bridge.unread_notifications", "params":{"account":"initminer"}, "id":1}]' http://localhost:$HIVEMIND_PORT | jq -r
}

testjussicom() {
  set -x
  curl -s --data '[{"jsonrpc":"2.0", "method":"bridge.unread_notifications", "params":{"account":"initminer"}, "id":1}]' http://localhost:$JUSSI_PORT | jq -r
}

dbactivity() {
  # -x for expanded display or the output will be messed up
  docker exec -i $POSTGRES_CONTAINER psql -x -c "select * from pg_stat_activity where datname='$POSTGRES_DB'"
}

help() {
  echo -e "$txtcyn
Usage: $0 COMMAND$reset
$txtred
Note: sudo required for some operations$reset
$txtcyn
Commands:
 preinstall    - preinstall tools and NTP synchronization
 installdocker - install docker and docker-compose
 build         - stop the running containers and (re)build all the images

 initdb        - initialize database cluster (e.g. postgresql database)
 importdb      - download and import the database dump
 dumpdb        - dump the database (compressed binary file) from postgresql

 start|stop|restart (e.g. start all)
           all - initdb+postgresql+hivemind
      postgres - postgresql container (with initdb dependency)
      hivemind - hivemind container (with postgresql dependency)
         jussi - jussi reverse proxy
 enter         - enter a container with bash shell; e.g. enter hivemind
 logs          - live logs of the running containers
 status        - check the containers status

 testhivemind  - test a hivemind API call to hivemind
 testjussi     - test a steemd API call to jussi
 testhivecom   - test a hivemind-communities API call to hivemind
 testjussicom  - test a hivemind-communities API call to jussi

 dbsize        - check the database size
 dbactivity    - check the database activity
  $reset"
  exit
}

case $1 in
  preinstall)
    preinstall
  ;;
  installdocker)
    installdocker
  ;;
  build)
    build
  ;;
  initdb)
    initdb
  ;;
  importdb)
    importdb
  ;;
  dumpdb)
    dumpdb
  ;;
  logs)
    logs
  ;;
  status)
    status
  ;;
  testhivemind)
    testhivemind
  ;;
  testjussi)
    testjussi
  ;;
  testhivecom)
    testhivecom
  ;;
  testjussicom)
    testjussicom
  ;;
  dbsize)
    dbsize
  ;;
  dbactivity)
    dbactivity
  ;;
  *)
    help
  ;;
esac
