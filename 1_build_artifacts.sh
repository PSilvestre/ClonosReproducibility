#!/bin/bash



if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
	docker_username=$(docker info | sed '/Username:/!d;s/.* //')
	CLONOS_IMG="$docker_username/clonos_repro_build"
	FLINK_IMG="$docker_username/flink_repro_build"
fi


if [ ! -d "./Clonos" ]; then

	if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 0 ]; then
		echoinfo "Building Clonos and Flink to populate build cache for BEAM"
	fi

  echoinfo "Cloning Clonos"
  git clone https://github.com/delftdata/Clonos >/dev/null 2>&1
  echoinfo "Building Clonos using Maven"
  pushd ./Clonos > /dev/null 2>&1
  mvn clean install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

	if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
	  echoinfo "Building docker image for Clonos named: $CLONOS_IMG"
	  jar_loc="./flink-contrib/docker-flink/beam-jars"
	  mkdir -p $jar_loc
	  cp ../beam-jars/* $jar_loc/
	  rm $jar_loc/*flink*.jar #Remove the flink jar
	
	  pushd ./flink-contrib/docker-flink >/dev/null 2>&1
	  ./build.sh --from-local-dist --image-name $CLONOS_IMG >/dev/null 2>&1
	  popd >/dev/null 2>&1 #back to ./Clonos
	  rm -rf $jar_loc      #Clean up the beam-jars folder
	fi

  echoinfo "Switching to Flink branch"
  git checkout flink1.7 >/dev/null 2>&1
  echoinfo "Building Flink using Maven"
  mvn clean install -DskipTests -Dcheckstyle.skip >/dev/null 2>&1

	if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
		echoinfo "Building docker image for Flink named: $FLINK_IMG"
  	jar_loc="./flink-contrib/docker-flink/beam-jars"
  	mkdir -p $jar_loc
  	cp ../beam-jars/* $jar_loc/
  	rm $jar_loc/*clonos*.jar #Remove the clonos jar

  	pushd ./flink-contrib/docker-flink >/dev/null 2>&1
  	./build.sh --from-local-dist --image-name $FLINK_IMG >/dev/null 2>&1
  	popd > /dev/null 2>&1 #back to ./Clonos
  	rm -rf $jar_loc
	fi
  popd > /dev/null 2>&1 #back to script home dir

	if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
		echoinfo "Pushing docker images to docker hub so they can be fetched by Kubernetes cluster. This may take a while..."
  	echoinfo "Docker user name: $docker_username"

  	docker push $CLONOS_IMG >/dev/null 2>&1
  	docker push $FLINK_IMG >/dev/null 2>&1
	fi

else
  echoinfo "Skipping build from source because ./Clonos already exists. Using images presumably built earlier: $CLONOS_IMG and $FLINK_IMG"
fi

