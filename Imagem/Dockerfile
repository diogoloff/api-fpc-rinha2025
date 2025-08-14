FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

COPY . /docker_build

RUN apt-get update && \
    apt-get install -y libcurl4 && \
	/docker_build/app/install.sh && \
    /docker_build/limpeza.sh && \
	apt-get clean

ENTRYPOINT ["/opt/rinha/app.init"]
