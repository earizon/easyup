#!/bin/bash
set -u

export DATE=`date +%Y%m%d_%H.%M`
OUTPUT="output.${DATE}.log"

exec 3>&1   # Copy current STDOUT to &3
exec 4>&2   # Copy current STDERR to &4
echo "Redirecting STDIN/STDOUT to $OUTPUT"
# exec 1>$OUTPUT 2>&1  
# REF: https://unix.stackexchange.com/questions/145651/using-exec-and-tee-to-redirect-logs-to-stdout-and-a-log-file-in-the-same-time
exec &> >(tee -a "$OUTPUT") # Reditect STDOUT/STDERR to file
exec 2>&1  

WD=$(pwd)

CONFIG_FILE=etc/easyup.conf # 

# REFERA_POSTFIX is the destination backup directory taken as
# reference by rsync. If same file exists, a link (vs full copy)
# is created, saving lot of space.

REFERA_POSTFIX=`echo -n "." ; date +%Y%m%d --date="-1 day"`
TARGET_POSTFIX=`echo -n "." ; date +%Y%m%d                `

echo -n "start: " ; date

GLOBAL_EXIT_STATUS=0

ERROR=""
function funThrow {
    if [[ $STOP_ON_ERROR != false ]] ; then
      echo "ERROR DETECTED: Aborting now due to" 
      echo -e ${ERROR} 
      exit 1;
    else
      echo "ERROR DETECTED: "
      echo -e ${ERROR}
      echo "WARN: CONTINUING WITH ERRORS "
      GLOBAL_EXIT_STATUS=1
    fi
    ERROR=""
}

function funPreChecks {
  if [ -e var/build_config ] ; then
     sh var/build_config > $CONFIG_FILE
  fi
  
  if [ -f easyUpDefaults ]; then
    . easyUpDefaults  # Apply extra defaults (Common options to all directories)
  fi
  RSYNC_DEFAULT_OPTS="${RSYNC_DEFAULT_OPTS} --recursive -a --delete --ignore-errors --checksum "
  if [ ! "${SSH_KEY}" ]; then
    ERROR="SSH_KEY not defined"
    funThrow
  fi
}


function funSync {
  for lineN in $(cat ${CONFIG_FILE} | grep -v "^#") ; do
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
     RSYNC_EXTRA_DIR_OPTS=""
     if [ -f $SRC/easyup.conf ] ; then
         source $SRC/easyup.conf
         RSYNC_EXTRA_DIR_OPTS="${RSYNC_DEFAULT_OPTS}"
     fi
     if [ -f $SRC/easyup.sh ] ; then
         bash -x $SRC/easyup.sh 1>$SRC/easyup.sh.log 2>&1
     fi
     if [[ -f $SRC || -d $SRC ]] ; then
         if [[ -d $SRC ]] ; then 
             echo $DATE > ${SRC}/easyup.last_backup_date
         else
             echo $DATE > ${SRC}.easyup.last_backup_date 
         fi
         SRC_REFERA=`echo -n ${DST_DIR0} ; echo ${SRC}${REFERA_POSTFIX} | sed "s/[/]/_/g"`
         # It could be the case that SRC_REFERA is a symlink to a symlink to a symlink ...
         # Use original (non-symlink) backup reference
         REMOTE_SCRIPT="readlink -f ${SRC_REFERA}" 
         
         SRC_REFERA=$(ssh -i ${SSH_KEY} -T -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" )
         SRC_TARGET=`echo -n ${DST_DIR0} ; echo ${SRC}${TARGET_POSTFIX} | sed "s/[/]/_/g"`
         if [ -n ${SRC_REFERA} ]; then
             RSYNC_FULL_OPTS="${RSYNC_DEFAULT_OPTS} ${RSYNC_EXTRA_DIR_OPTS} --link-dest ${SRC_REFERA} "
         else
             RSYNC_FULL_OPTS="${RSYNC_DEFAULT_OPTS} ${RSYNC_EXTRA_DIR_OPTS}                           "
         fi
         rsync -e "ssh -i ${SSH_KEY} -T -p ${DST_PORT}" ${RSYNC_FULL_OPTS} ${SRC} ${DST_USER}@${DST_HOST}:${SRC_TARGET}  || echo -n ""

         # Create sym link if ssh skips backup (no modifications found)
         REMOTE_SCRIPT="if [[ ! -f $SRC_TARGET && ! -d $SRC_TARGET ]] ; then ln -s ${SRC_REFERA} ${SRC_TARGET} ; fi" 
         ( ssh -i ${SSH_KEY} -T -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" ) &
     else
         ERROR="ERROR: failed $SRC copy due to: ${SRC} must be a file or directory"
         GLOBAL_EXIT_STATUS=1
     fi
     echo "debug: lineN: $lineN end ${ERROR}"
  done
}

(echo -n "end: " ; date )

cd $WD ; funPreChecks
cd $WD ; funSync

echo "Exiting with status:$GLOBAL_EXIT_STATUS"
exit $GLOBAL_EXIT_STATUS
