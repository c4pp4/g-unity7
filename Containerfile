# Build environment for the source packages, the same as in GitHub Actions.
FROM docker.io/library/ubuntu:26.10

COPY scripts/deps.txt /tmp/deps.txt
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends $(cat /tmp/deps.txt) \
	&& rm -rf /var/lib/apt/lists/* /tmp/deps.txt
