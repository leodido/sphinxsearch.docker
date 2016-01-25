# SphinxSearch Builder
#
# @author 	leodido <leodidonato@gmail.com> @leodido
FROM debian:wheezy
MAINTAINER Leonardo Di Donato <leodidonato@gmail.com> @leodido
RUN apt-get update && apt-get install -y curl autoconf automake libtool build-essential unixodbc-dev libmysqlclient-dev libexpat-dev bison flex libreadline-dev
COPY scripts/make.bash scripts/indexall.sh scripts/searchd.sh /
ENTRYPOINT ["/make.bash"]