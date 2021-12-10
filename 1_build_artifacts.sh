#!/bin/bash

#Clone Clonos


docker_username=$(docker info | sed '/Username:/!d;s/.* //')
CLONOS_IMG="$docker_username/clonos_repro_build"
FLINK_IMG="$docker_username/flink_repro_build"


if [ ! -d "./Clonos" ]; then

  echoinfo "Cloning Clonos"
  git clone https://github.com/delftdata/Clonos >/dev/null 2>&1
  echoinfo "Building Clonos using Maven"
  pushd ./Clonos > /dev/null 2>&1
  mvn clean install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

  echoinfo "Building docker image for Clonos named: $CLONOS_IMG"
  jar_loc="./flink-contrib/docker-flink/beam-jars"
  mkdir -p $jar_loc
  cp ../beam-jars/* $jar_loc/
  rm $jar_loc/*flink*.jar #Remove the flink jar

  pushd ./flink-contrib/docker-flink >/dev/null 2>&1
  ./build.sh --from-local-dist --image-name $CLONOS_IMG >/dev/null 2>&1
  popd >/dev/null 2>&1 #back to ./Clonos
  rm -rf $jar_loc      #Clean up the beam-jars folder

  echoinfo "Switching to Flink branch"
  git checkout flink1.7 >/dev/null 2>&1
  echoinfo "Building Flink using Maven"
  mvn clean install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

  echoinfo "Building docker image for Flink named: $FLINK_IMG"
  jar_loc="./flink-contrib/docker-flink/beam-jars"
  mkdir -p $jar_loc
  cp ../beam-jars/* $jar_loc/
  rm $jar_loc/*clonos*.jar #Remove the clonos jar

  pushd ./flink-contrib/docker-flink >/dev/null 2>&1
  ./build.sh --from-local-dist --image-name $FLINK_IMG >/dev/null 2>&1
  popd > /dev/null 2>&1 #back to ./Clonos
  rm -rf $jar_loc
  popd > /dev/null 2>&1 #back to script home dir

  echoinfo "Pushing docker images to docker hub so they can be fetched by Kubernetes cluster. This may take a while..."
  echoinfo "Docker user name: $docker_username"

  docker push $CLONOS_IMG >/dev/null 2>&1
  docker push $FLINK_IMG >/dev/null 2>&1

else
  echoinfo "Skipping build of docker images because ./Clonos already exists. Using images presumably built earlier: $CLONOS_IMG and $FLINK_IMG"
fi

