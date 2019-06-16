Hivemind and PostgreSQL docker
===
Hive (https://github.com/steemit/hivemind) is a "consensus interpretation" layer for the Steem blockchain, maintaining the state of social features such as post feeds, follows, and communities. Written in Python, it synchronizes an SQL database with chain state, providing developers with a more flexible/extensible alternative to the raw steemd API.

Table of Contents
=================
<!--ts-->
   * [Requirements](#requirements)
   * [Git installation](#git-installation)
   * [Preparation](#preparation)
   * [Running Postgres](#running-postgres)
   * [Importing database dump](#importing-database-dump)
   * [Running Hivemind](#running-hivemind)
   * [Running Hivemind and Postgres simultaneously](#running-hivemind-and-postgres-simultaneously)
   * [Testing Hivemind](#testing-hivemind)
   * [Running Jussi](#running-jussi)
   * [Checking the logs](#checking-the-logs)
   * [Project command options](#project-command-options)
   * [Notes](#notes)
<!--te-->

## Requirements
- Docker Engine 18.06.0+
- PostgreSQL 10+
- 2.5GB of memory for hivemind synch process
- 250GB storage for the database

## Git Installation
```
git clone https://github.com/Jolly-Pirate/hivemind-docker.git
cd hivemind-docker
chmod +x run.sh
```

## Preparation
Do the following steps sequentially:

1. Copy the .env file\
`cp .env.example .env`
2. Carefully edit all the variables in the .env file and save\
`nano .env`
3. Preinstall tools and NTP synchronization\
`./run.sh preinstall`
4. Install docker and docker-compose\
`./run.sh installdocker`
5. Build the needed containers\
`./run.sh build`


## Running Postgres
Hivemind requires a postgres backend. Start postgres with these two commands consecutively:

`./run.sh initdb` (will initialize a fresh database cluster)\
`./run.sh start pg` (will start postgres using the credentials from .env)

## Importing database dump
For an efficient way to get hivemind going with a short DB synchronization, download a database dump (from a daily postgres snapshot), and import it. The dump was done with PostgreSQL 10.8. ETA depends on your internet speed, storage and CPU.

`./run.sh importdb`

**ETA ~3h**

## Running Hivemind
After the DB import, start hivemind to synchronize the missing blocks.

`./run.sh start hive`

**ETA ~1h**

## Running Hivemind and Postgres simultaneously
If you didn't do the 3 steps above, hivemind can be ran from scratch, the script will create a new postgres database, then synchronize it with an endpoint RPC server. However be advised that this approach is lenghthy, depending on your machine specs. For this *plug-n-play* solution, run the following command:

`./run.sh start all`

 **ETA few days**

To stop the hivemind and postgres containers

`./run.sh stop all`

If you already imported the database, doing `./run.sh start all` will resume synchronization from the last processed block.

## Testing Hivemind
Once hivemind is fully synchronized, you can test it by querying it on the port you defined in `.env`, for example `HIVEMIND_PORT=8080`:

`./run.sh testhive`

which runs this command:

`curl -s --data '[{"jsonrpc":"2.0", "method":"condenser_api.get_follow_count", "params":{"account":"initminer"}, "id":1}]' http://localhost:8080 | jq -r`

and gives this result:
```
[
  {
    "jsonrpc": "2.0",
    "result": {
      "account": "initminer",
      "following_count": 0,
      "follower_count": 15
    },
    "id": 1
  }
]
```

## Running Jussi
Jussi is an optional reverse proxy, its configuration won't be covered in this guide. You can check it out at https://github.com/steemit/jussi

Edit and place the DEV_config.json file in the hivemind-docker folder, then start it with:

`./run.sh start jussi`

You can test it with

`./run.sh testjussi`

## Checking the logs
At any time, you can check the logs with:

`./run.sh logs`

Press `ctrl-c` to stop following the logs.

## Project command options
The commands for managing the docker project are listed by typing:

`./run.sh`

Here's a summary of the available commands:
```
 preinstall    - preinstall tools and NTP synchronization
 installdocker - install docker and docker-compose
 build         - stop the running containers and (re)build all the images

 initdb        - initialize database cluster (e.g. postgresql database)
 importdb      - download and import the database dump

 start|stop|restart (e.g. start all)
           all - initdb+postgresql+hivemind
      postgres - postgresql container (with initdb dependency)
          hive - hivemind container (with postgresql dependency)
         jussi - jussi reverse proxy
 enter         - enter a container with bash shell; e.g. enter hive
 logs          - live logs of the running containers
 status        - check the containers status

 testhive      - test a hive API call to hivemind
 testjussi     - test a steemd API call to jussi

 dbsize        - check the database size
 dbactivity    - check the database activity
```

## Notes
I'm using docker-compose for this project because of its flexibility in managing multiple containers, and to minimize the use of long complicated docker cli commands. With dependency checks in the scripts, I covered many possibilities to make a hivemind deployment easy.

---
###### tags: `steemd` `hivemind` `postgresql` `blockchain` `database` `docker` `docker-compose`