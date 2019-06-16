FROM ubuntu:18.04

# ARG variables accessible only during the build process
ARG POSTGRES_USER
ARG POSTGRES_PASSWORD
ARG POSTGRES_DB

RUN apt-get update &&\
  apt-get upgrade -y &&\
  apt-get install -y wget nano gnupg2 sudo iputils-ping net-tools netcat &&\
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - &&\
  echo "deb http://apt.postgresql.org/pub/repos/apt/ $(. /etc/os-release; echo ${VERSION_CODENAME})-pgdg main" > /etc/apt/sources.list.d/PostgreSQL.list &&\
  apt-get install -y postgresql-10 &&\
  apt-get clean -qy

# Execute sudo without password, needed later for the entrypoint.sh script to give permissions on /temp
RUN adduser postgres sudo && sed -i /etc/sudoers -re 's/^%sudo.*/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/g'

RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/10/main/pg_hba.conf &&\
  echo "listen_addresses='*'" >> /etc/postgresql/10/main/postgresql.conf &&\
  sed -i /etc/postgresql/10/main/postgresql.conf -re '/max_wal_size/s/^#//g' &&\
  sed -i /etc/postgresql/10/main/postgresql.conf -re 's/max_wal_size = 1GB/max_wal_size = 5GB/g' &&\
  sed -i /etc/postgresql/10/main/pg_hba.conf -re 's/(^local.*all.*all.*)peer/\1md5/g'

# Run the rest of the commands as the 'postgres' user created by the apt-get install
USER postgres

# Expose the PostgreSQL port
EXPOSE 5432

ADD --chown=postgres:postgres entrypoint.sh /
RUN chmod 700 /entrypoint.sh
