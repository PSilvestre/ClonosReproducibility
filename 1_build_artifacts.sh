#!/bin/bash



if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
	docker_username=$(docker info | sed '/Username:/!d;s/.* //')
	CLONOS_IMG="$docker_username/clonos_repro_build"
	FLINK_IMG="$docker_username/flink_repro_build"
fi


if [ ! -d "./Clonos" ]; then

	if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 0 ]; then
	  # Check if build cache has folders for testing vesions of clonos and flink. If so, can skip build step.
	  m2_path="~/.m2/repository/org/apache/flink/flink-runtime_2.11"
	  if [ -d "$m2_path/1.7-CLONOS-SNAPSHOT/" && -d "$m2_path/1.7-FLINK-SNAPSHOT/" ] ; then
	    return
	  else
		  echoinfo ".m2 cache does not contain Clonos build files."
		  echoinfo "Building Clonos and Flink to populate build cache for BEAM"
	  fi
	fi

  echoinfo "Cloning Clonos"
  git clone https://github.com/delftdata/Clonos >/dev/null 2>&1
  echoinfo "Building Clonos using Maven"
  pushd ./Clonos > /dev/null 2>&1
  # Single-threaded build. Attempts to build in parallel (using -T 16) fail due to unspecified dependencies between submodules.
  mvn clean install -Dmaven.artifact.threads=16 -DskipTests -Dcheckstyle.skip -Dfast >/dev/null 2>&1

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
  # Single-threaded build. Attempts to build in parallel (using -T 16) fail due to unspecified dependencies between submodules.
  mvn clean install -Dmaven.artifact.threads=16 -DskipTests -Dcheckstyle.skip -Dfast >/dev/null 2>&1

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

