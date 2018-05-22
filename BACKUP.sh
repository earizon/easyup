#!/bin/bash
set -u

export DATE=`date +%Y%m%d_%H.%M`


CONFIG_FILE=etc/easyup.conf
ERROR_OUTPUT="error.${DATE}.log"

exec 1>output.${DATE}.log 2>$ERROR_OUTPUT

echo -n "" > $ERROR_OUTPUT
if [ -f var/build_config ] ; then
.  var/build_config
fi
RSYNC_OPTS=""
RSYNC_DEFAULT_OPTS="-avh --delete --ignore-errors " 
RSYNC_FULL_OPTS="${RSYNC_DEFAULT_OPTS}" # default

cat ${CONFIG_FILE} | grep -v "^#" | while read lineN ; do
   SRC=$(     echo $lineN | cut -d ":" -f 1)
   DST_USER=$(echo $lineN | cut -d ":" -f 2)
   DST_HOST=$(echo $lineN | cut -d ":" -f 3)
   DST_PORT=$(echo $lineN | cut -d ":" -f 4)
   DST_DIR0=$(echo $lineN | cut -d ":" -f 5)
   if [ -f $SRC/easyup.conf ] ; then
       source $SRC/easyup.conf
       RSYNC_FULL_OPTS="${RSYNC_DEFAULT_OPTS} ${RSYNC_OPTS}"
   fi
   if [ -f $SRC/easyup.sh ] ; then
       bash -x $SRC/easyup.sh 1>$SRC/easyup.sh.log 2>&1
   fi
if [[ -f $SRC || -d $SRC ]] ; then
    rsync -e "ssh -p ${DST_PORT}" ${RSYNC_FULL_OPTS} ${SRC} ${DST_USER}@${DST_HOST}:${DST_DIR0}
else
    echo "failed $SRC copy due to: ${SRC} must be a file or directory" > ${ERROR_OUTPUT}
    continue
fi

done
