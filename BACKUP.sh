#!/bin/bash
set -u

export DATE=`date +%Y%m%d_%H.%M`

CONFIG_FILE=etc/easyup.conf
ERROR_OUTPUT="error.${DATE}.log"

exec 1>output.${DATE}.log 2>$ERROR_OUTPUT

REFERA_POSTFIX=`echo -n "." ; date +%Y%m%d --date="-1 day"`
TARGET_POSTFIX=`echo -n "." ; date +%Y%m%d                `
echo -n "" > $ERROR_OUTPUT
if [ -f var/build_config ] ; then
.  var/build_config
fi
RSYNC_OPTS=""
RSYNC_DEFAULT_OPTS="-avh --delete --ignore-errors --checksum" 


cat ${CONFIG_FILE} | grep -v "^#" | while read lineN ; do
   ERROR=""
   echo "debug: lineN: $lineN start"
   RSYNC_EXTRA_DIR_OPTS=""
   SRC=$(     echo $lineN | cut -d ":" -f 1)
   if [[ -d $SRC ]] ; then
       # Append "/" to dirs.  rsync is very sensitive to this "/".
       # It will copy contents of dir if present or the dir itself if not
       if [[ $SRC      != */ ]] ; then SRC="${SRC}/"           ; fi
   fi
   DST_USER=$(echo $lineN | cut -d ":" -f 2)
   DST_HOST=$(echo $lineN | cut -d ":" -f 3)
   DST_PORT=$(echo $lineN | cut -d ":" -f 4)
   DST_DIR0=$(echo $lineN | cut -d ":" -f 5)
   # Avoid problems. Always append "/" to the end for dirs
   if [[ $DST_DIR0 != */ ]] ; then DST_DIR0="${DST_DIR0}/" ; fi
   if [ -f $SRC/easyup.conf ] ; then
       source $SRC/easyup.conf
       RSYNC_EXTRA_DIR_OPTS="${RSYNC_DEFAULT_OPTS} ${RSYNC_OPTS}"
   fi
   if [ -f $SRC/easyup.sh ] ; then
       bash -x $SRC/easyup.sh 1>$SRC/easyup.sh.log 2>&1
   fi
   if [[ -f $SRC || -d $SRC ]] ; then
       if [[ -d $SRC ]] ; then 
           echo $DATE > $SRC/easyup.last_backup_date
       else
           echo $DATE > $SRC.easyup.last_backup_date 
       fi
       SRC_REFERA=`echo -n ${DST_DIR0} ; echo ${SRC}${REFERA_POSTFIX} | sed "s/[/]/_/g"`
       SRC_TARGET=`echo -n ${DST_DIR0} ; echo ${SRC}${TARGET_POSTFIX} | sed "s/[/]/_/g"`
       RSYNC_FULL_OPTS="${RSYNC_EXTRA_DIR_OPTS} --link-dest ${SRC_REFERA} "
       rsync -e "ssh -p ${DST_PORT}" ${RSYNC_FULL_OPTS} ${SRC} ${DST_USER}@${DST_HOST}:${SRC_TARGET}  || echo -n ""
       # Create sym link if ssh skips backup (no modifications found)
       REMOTE_SCRIPT="if [[ ! -f $SRC_TARGET && ! -d $SRC_TARGET ]] ; then ln -s ${SRC_REFERA} ${SRC_TARGET} ; fi" 
       ( ssh -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" ) &
   else
       ERROR="failed $SRC copy due to: ${SRC} must be a file or directory" > ${ERROR_OUTPUT}
   fi
   echo "debug: lineN: $lineN end ${ERROR}"
done

# https://mail.google.com/mail/u/0/#search/backup+script/11c9389117b129b8
