#!/usr/bin/env bats

MYSQL_IMG=testmysql
MYSQL_DB=test
MYSQL_PORT=3306
INDEXER_IMG=testindexer
SEARCHD_IMG=testsearchd
SEARCHD_PORT=9306

@test "before all" {
  # current TAG
  TAG=${BATS_TEST_FILENAME%.*}
  TAG=${TAG%.*}
  TAG=${TAG#*-}

  # current context directory
  CONTEXT_DIR=${BATS_TEST_DIRNAME}/context/mysql

  # current docker image
  IMG="leodido/sphinxsearch:${TAG}"
  docker history "${IMG}" >/dev/null 2>&1

  # start mysql
  docker run --name ${MYSQL_IMG} -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -e MYSQL_DATABASE=${MYSQL_DB} -d mysql:latest
  # wait to store data until mysql is ready
  TESTMYSQL_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${MYSQL_IMG})
  while ! nc ${TESTMYSQL_HOST} ${MYSQL_PORT} > /dev/null 2>&1 < /dev/null;
  do
    sleep 1
  done
  docker exec -i ${MYSQL_IMG} mysql ${MYSQL_DB} < ${CONTEXT_DIR}/script.sql

  # run indexall script, keeping it running for testing purposes (note that a daemonized run is usally not needed for the indexing)
  docker run --link ${MYSQL_IMG}:${MYSQL_IMG} --name ${INDEXER_IMG} -v ${CONTEXT_DIR}:/usr/local/etc -d ${IMG} sh -c "indexall.sh; tail -f /dev/null"

  # run searchd script
  docker run --name ${SEARCHD_IMG} --volumes-from ${INDEXER_IMG} -p 127.0.0.1:${SEARCHD_PORT}:${SEARCHD_PORT} -d ${IMG} searchd.sh

  # NOTE
  # given the indexer container and the searchd container
  # do not share some directories (e.g., /var/run/sphinx)
  # some features will not work (e.g., rotating)
  # with this setting
}

@test "[indexall] should read the shared config" {
  run docker logs ${INDEXER_IMG}
  [[ ${output} =~ "using config file '/usr/local/etc/sphinx.conf'" ]]
}

@test "[indexall] should index the plain indexes" {
  run docker logs ${INDEXER_IMG}
  [[ ${output} =~ "indexing index" ]]
}

@test "[indexall] should  the real time indexes" {
  run docker logs ${INDEXER_IMG}
  [[ ${output} =~ "ping non-plain index" ]]
}

@test "[indexall] should create the spx files" {
  ifiles=($(echo plain.sp{a,d,e,h,i,k,m,p,s}))
  for f in "${ifiles[@]}"
  do
    run docker exec -t ${INDEXER_IMG} test -e /var/idx/sphinx/${f}
    [ ${status} -eq 0 ]
  done
}

@test "[indexall] should create plain tables" {
  TESTSEARCHD_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${SEARCHD_IMG})
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SHOW TABLES;'
  [[ ${output} =~ "plain" ]]
  [[ ${output} =~ "local" ]]
}

@test "[searchd] should read the shared config" {
  run docker logs ${SEARCHD_IMG}
  [[ ${lines[0]} =~ "using config file '/usr/local/etc/sphinx.conf'" ]]
}

@test "[searchd] should precache indexes" {
  run docker logs ${SEARCHD_IMG}
  [[ ${output} =~ "index 'plain'" ]]
  [[ ${output} =~ "index 'realtime'" ]]
}

@test "[searchd] should create the lock files" {
  run docker exec -t ${SEARCHD_IMG} test -e /var/idx/sphinx/realtime.lock
  ifiles=(realtime.lock)
  for f in "${ifiles[@]}"
  do
    run docker exec -t ${SEARCHD_IMG} test -e /var/idx/sphinx/${f}
    [ ${status} -eq 0 ]
  done
}

@test "[searchd] should create real-time tables" {
  TESTSEARCHD_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${SEARCHD_IMG})
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SHOW TABLES;'
  [[ ${output} =~ 'realtime' ]]
  [[ ${output} =~ 'rt' ]]
}

@test "[searchd] should accept connections" {
  run docker logs ${SEARCHD_IMG}
  [ ${lines[@]:(-1)} = 'accepting connections' ]
  run nc -zv 127.0.0.1 ${SEARCHD_PORT}
  [[ ${output} =~ 'succeeded' ]]
}

@test "[searchd] should serve queries" {
  TESTSEARCHD_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${SEARCHD_IMG})
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SELECT COUNT(*) FROM plain;'
  [ ${output} = 4 ]
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "SELECT * FROM plain WHERE MATCH('this is my');"
  [ ${#lines[@]} = 2 ]
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "SELECT * FROM plain WHERE MATCH('this is');"
  [ ${#lines[@]} = 4 ]
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SELECT COUNT(*) FROM realtime;'
  [ ${output} = 0 ]
}

@test "[searchd] should index real-time data" {
  TESTSEARCHD_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${SEARCHD_IMG})
  docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "INSERT INTO realtime VALUES (1, 'a random title', 'some runtime data', 2);"
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SELECT COUNT(*) FROM realtime;'
  [ ${output} = 1 ]
  docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "INSERT INTO realtime VALUES (2, 'a runtime title', 'some content data', 1);"
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e 'SELECT COUNT(*) FROM realtime;'
  [ ${output} = 2 ]
  run docker exec  ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "SELECT COUNT(*) FROM realtime WHERE MATCH('@content runtime');"
  [ ${output} = 1 ]
  run docker exec ${MYSQL_IMG} mysql -h ${TESTSEARCHD_HOST} -P ${SEARCHD_PORT} ${MYSQL_DB} -sN -e "SELECT COUNT(*) FROM realtime WHERE MATCH('runtime');"
  [ ${output} = 2 ]
}

@test "after all" {
  docker rm -fv ${MYSQL_IMG}
  docker rm -fv ${INDEXER_IMG}
  docker rm -fv ${SEARCHD_IMG}
}
