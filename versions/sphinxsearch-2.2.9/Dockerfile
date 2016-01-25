# Sphinxsearch
#
# @version 	latest (2.2.9)
# @author 	leodido <leodidonato@gmail.com> (@leodido)
FROM debian:wheezy
MAINTAINER Leonardo Di Donato <leodidonato@gmail.com> @leodido
# runtime dependencies
RUN apt-get update && apt-get install -y unixodbc-dev libexpat-dev
# place sphinxsearch installation in place
ADD /sphinxsearch.tar.gz /usr/local/
ADD dicts /var/diz/sphinx
# expose ports
EXPOSE 9312 9306
# expose directories
VOLUME ["/var/idx/sphinx", "/var/log/sphinx", "/var/lib/sphinx", "/var/run/sphinx", "/var/diz/sphinx"]