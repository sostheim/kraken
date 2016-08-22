#/bin/bash

set -e

cd

if [[ -e $UTILS_PATH/socat ]]; then
  exit 0
fi

wget "$SOCAT_URL"
mv ./socat $UTILS_PATH/socat
chmod 755 $UTILS_PATH/socat