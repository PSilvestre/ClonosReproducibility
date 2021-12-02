#!/bin/bash

#Clone Clonos
if [ ! -d "./Clonos" ]; then
  echoinfo "Cloning Clonos"
  git clone https://github.com/delftdata/Clonos
  echoinfo "Building Clonos using Maven"
  pushd ./Clonos
  mvn install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

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
  git checkout flink1.7
  echoinfo "Building Flink using Maven"
  mvn install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

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

  if [ "$REMOTE" = "1" ]; then
    echoinfo "Pushing docker images to docker hub so they can be fetched by Kubernetes cluster..."
    docker push $CLONOS_IMG >/dev/null 2>&1
    docker push $FLINK_IMG >/dev/null 2>&1
  fi
else
  echoinfo "Skipping build of docker images from as ./Clonos already exists. Using images built earlier: $CLONOS_IMG and $FLINK_IMG"
fi

if [ ! -d "./beam" ]; then
  echoinfo "Cloning Clonos' Beam implementation for NEXMARK experiments"
  git clone https://github.com/delftdata/beam
else
  echoinfo "Skipping git clone of beam because directory already present."
fi
