ARG SPARK_VERSION=3.1.3
ARG BIGSTITCHER_SPARK_GIT_TAG=main

# Temporary container for building cleanly
FROM janeliascicomp/builder:1.3.0 as builder
ARG BIGSTITCHER_SPARK_GIT_TAG

# Checkout and build the code
WORKDIR /tmp/app
# TODO: currently this points to a fork which adds a minor feature. It can be switched back to https://github.com/saalfeldlab/stitching-spark after the PR is merged.
RUN git clone --branch ${BIGSTITCHER_SPARK_GIT_TAG} --depth 1 https://github.com/JaneliaSciComp/BigStitcher-Spark.git . \
    && /usr/local/bin/buildinfo.sh \
    && mvn clean package -P fatjar

# Find the built jar, based on the version in the pom file
RUN xq -r '.project.artifactId+"-"+.project.version+".jar"' pom.xml > filename \
    && mv /tmp/app/target/`cat filename` app.jar

RUN echo "$BIGSTITCHER_SPARK_GIT_TAG" > /tmp/app/VERSION

# Create final image
FROM multifish/biocontainers-spark:${SPARK_VERSION}
ARG BIGSTITCHER_SPARK_GIT_TAG

LABEL software="bigstitcher-spark" \
    base_image="apache/spark" \
    container="bigstitcher-spark" \
    about.summary="Running compute-intense parts of BigStitcher distributed" \
    about.home="https://github.com/JaneliaSciComp/BigStitcher-Spark" \
    software.version=${BIGSTITCHER_SPARK_GIT_TAG} \
    upstream.version=${BIGSTITCHER_SPARK_GIT_TAG} \
    version="1" \
    about.license="BSD-2-Clause" \
    about.license_file="/app/LICENSE.txt" \
    extra.binaries="/opt/spark/bin" \
    about.tags="implemented-in::java, interface::commandline, role::program" \
    bioimagetools.image.authors="kawaset@janelia.hhmi.org"

WORKDIR /app
COPY --from=builder /tmp/app/LICENSE /app/LICENSE
COPY --from=builder /tmp/app/VERSION /app
COPY --from=builder /tmp/app/app.jar /app
COPY --from=builder /buildinfo /app