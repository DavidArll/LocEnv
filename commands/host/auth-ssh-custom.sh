#!/bin/bash

set -e 

docker run -it --rm --volumes-from=ddev-ssh-agent \
  --user=501 \
  --entrypoint= \
  --mount=type=bind,src=/Users/c.de.los.santos/.ssh/id_rsaDev2,dst=/tmp/sshtmp/id_rsaDev2 \
  ddev/ddev-ssh-agent:v1.24.2-built \
  bash -c "cp -r /tmp/sshtmp ~/.ssh && chmod -R go-rwx ~/.ssh && cd ~/.ssh && ssh-add id_rsaDev2"