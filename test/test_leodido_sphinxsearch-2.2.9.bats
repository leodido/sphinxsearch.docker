#!/usr/bin/env bats

setup() {
  # current tag
  tag=${BATS_TEST_FILENAME%.*}
  tag=${tag%.*}
  tag=${tag#*-}
  img="leodido/sphinxsearch:${tag}"

  docker history "${img}" >/dev/null 2>&1
  commands=("indexall.sh" "searchd.sh" "searchd" "indexer" "spelldump" "indextool" "wordbreaker")
  dicts=("de.pak" "ru.pak" "en.pak")
}

@test "should version be correct" {
  run docker run --rm "${img}" indexer
  [[ ${lines[0]} =~ "${tag}" ]]
}

@test "should cli scripts be correctly installed" {
  for c in "${commands[@]}"
  do
    # script paths should be correct
    run docker run --rm "${img}" which ${c}
    expected="/usr/local/bin/${c}"
    [ ${output} = ${expected} ]
    [ ${status} -eq 0 ]
    # scripts should have 755 permissions
    run docker run --rm "${img}" stat -c "%a" ${expected}
    [ ${output} = 755 ]
  done
}

@test "should contain lemma dicts" {
  for d in "${dicts[@]}"
  do
    # dict files should exist
    run docker run --rm "${img}" test -e /var/diz/sphinx/${d}
    [ ${status} -eq 0 ]
  done
}

@test "should ports be exposed" {
  run docker inspect -f '{{ range $key,$val := .Config.ExposedPorts }}{{println $key}}{{end}}' "${img}"
  [ `echo ${lines[0]} | sed -e 's/\/tcp//g'` = 9306 ]
  [ `echo ${lines[1]} | sed -e 's/\/tcp//g'` = 9312 ]
}

@test "should volumes be exposed" {
  run docker inspect -f '{{ range $key,$val := .Config.Volumes }}{{println $key}}{{end}}' "${img}"
  [ ${lines[0]} = "/var/diz/sphinx" ]
  [ ${lines[1]} = "/var/idx/sphinx" ]
  [ ${lines[2]} = "/var/lib/sphinx" ]
  [ ${lines[3]} = "/var/log/sphinx" ]
  [ ${lines[4]} = "/var/run/sphinx" ]
}
