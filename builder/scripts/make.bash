#!/usr/bin/env bash

# Build script
# @author   leodido   <leodidonato@gmail.com>

declare SPHINXSEARCH_BASE_URL=${SPHINXSEARCH_BASE_URL:-http://sphinxsearch.com/files/sphinx}
declare RE2_BASE_URL=${RE2_BASE_URL:-https://github.com/google/re2/archive}
declare LIBSTEMMER_URL=${LIBSTEMMER_URL:-http://snowball.tartarus.org/dist/libstemmer_c.tgz}
declare POSTGRESQL_VERSION=${POSTGRESQL_VERSION:-9.4.4}
declare POSTGRESQL_URL=${POSTGRESQL_URL:-https://ftp.postgresql.org/pub/source/v${POSTGRESQL_VERSION}/postgresql-${POSTGRESQL_VERSION}.tar.gz}
declare STDOUT=1

set -eo pipefail; [[ "$TRACE" ]] && set -x

[[ "$(id -u)" -eq 0 ]] || {
  printf >&2 '%s requires root\n' "$0" && exit 1
}

usage() {
  printf >&2 '%s -r release\n' "$0" && exit 1
}

output_redirect() {
  if [[ "$STDOUT" ]]; then
    cat - 1>&2 # redirect stdout to stderr
  else
    cat -
  fi
}

build() {
  if [ -z $1 ]; then
      exit 1
  fi
  declare version="$1"
  local prefix="/usr/local"
  local tmp="$(mktemp -d "${TMPDIR:-/var/tmp}/sphinxsearch-${version}-XXXXX")"

  # download postegresql source
  curl -sSL "${POSTGRESQL_URL}" | tar xz -C ${tmp} | output_redirect
  # postegresql installation
  (cd ${tmp}/postgresql-${POSTGRESQL_VERSION}; ./configure --prefix=${prefix}/pgsql;  make -j; make install) | output_redirect

  # download sphinxsearch source
  curl -sSL "${SPHINXSEARCH_BASE_URL}-${version}.tar.gz" | tar xz -C ${tmp} | output_redirect
  # download latest google re2 and place it
  local re2_tags=$(curl -k -sSL https://api.github.com/repos/google/re2/tags)
  local re2_latest_tag=$(echo "${re2_tags}" | grep "name" | head -n 1 | cut -d '"' -f 4)
  curl -k -sSL "${RE2_BASE_URL}/${re2_latest_tag}".tar.gz | tar xz -C ${tmp} | output_redirect
  mv ${tmp}/re2-${re2_latest_tag}/* ${tmp}/sphinx-${version}/libre2/
  # download latest libstemmer and place it
  curl -sSL "${LIBSTEMMER_URL}" | tar xz -C ${tmp} | output_redirect
  mv ${tmp}/libstemmer_c/* ${tmp}/sphinx-${version}/libstemmer_c/
  # fix eventually mispelled stemming file names
  sed -i -e 's/stem_ISO_8859_1_hungarian/stem_ISO_8859_2_hungarian/g' ${tmp}/sphinx-${version}/libstemmer_c/Makefile.in
  # sphinxsearch configuration
  (cd ${tmp}/sphinx-${version} && \
  ./configure --prefix=${prefix} \
              --enable-id64 \
              --with-static-mysql \
              --with-mysql-includes=$(mysql_config --variable=pkgincludedir) \
              --with-mysql-libs=$(mysql_config --variable=pkglibdir) \
              --with-static-pgsql \
              --with-pgsql-includes=${prefix}/pgsql/include \
              --with-pgsql-libs=${prefix}/pgsql/lib \
              --with-libstemmer \
              --with-re2 \
              --with-iconv \
              --with-libexpat \
              --with-unixodbc) | output_redirect
  # sphinxsearch installation
  (cd ${tmp}/sphinx-${version} && make -j install) | output_redirect

  # insert shortcut scripts
  mv indexall.sh searchd.sh -t ${prefix}/bin/

  # FIXME: is now ${prefix}/pgsql (statically linked) directory removable?

  # save
  tar -p -z -f /sphinxsearch.tar.gz --numeric-owner -C "${prefix}" -c .
  if [[ "$STDOUT" ]]; then
    cat /sphinxsearch.tar.gz
  else
    return 0
  fi
}

main() {
  while getopts ":r:" opt; do
      case ${opt} in
          r) VERSION="$OPTARG";;
          *) usage;;
      esac
  done
  build "$VERSION"
}

main "$@"
