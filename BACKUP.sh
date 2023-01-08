#!/bin/bash -x
set -u

# ------------------------------------
readonly OUTPUT="LOGS/$(basename $0).$(whoami).$(date +%Y%m%d_%Hh%Mm%Ss).log"
if [ ! -d LOGS ] ; then mkdir LOGS ; fi
ln -sf ${OUTPUT} link_last_log.$(basename $0).gitignore
exec 3>&1   # Copy current STDOUT to &3
exec 4>&2   # Copy current STDERR to &4
echo "Cloning STDOUT/STDERR to ${OUTPUT}"
exec &> >(tee -a "$OUTPUT")
exec 2>&1
echo "message logged to file & console"
# ------------------------------------

# Parsing Args ----------------------
DRYRUN=false
while [  $#  -gt 0 ]; do  # $#  number of arguments
  case "$1" in
    --dryrun)
      DRYRUN=true
      shift 1
      ;;
    *)
      echo "non-recognised option '$1'"
      shift
  esac
done
# ------------------------------------

cd "$(dirname $0)"
CWD=$(pwd)
export DATE=`date +%Y%m%d_%H.%M`

REFER0_POSTFIX=`echo -n "."                               `
REFERA_POSTFIX=`echo -n "." ; date +%Y%m%d --date="-1 day"`
TARGET_POSTFIX=`echo -n "." ; date +%Y%m%d                `
echo -n "start: " ; date

if [ -x var/build_config ] ; then
   var/build_config
fi

RSYNC_DEFAULT_OPTS=" --recursive -a --delete --ignore-errors --checksum "

export CONFIG_FILE=etc/easyup.conf


for lineN in $(cat ${CONFIG_FILE} | grep -v "^#") ; do
   cd $CWD
   ERROR=""
   echo "debug: $lineN: $lineN start"
   SRC=$(     echo $lineN | cut -d ":" -f 1)
   if [[ -d $SRC ]] ; then
       # Append "/" to dirs.  rsync is very sensible to this "/".
       # It will copy contents of dir if present or the dir itself if not
       if [[ $SRC      != */ ]] ; then SRC="${SRC}/"           ; fi
   fi
   cd $SRC
   DST_USER=$(echo $lineN | cut -d ":" -f 2)
   DST_HOST=$(echo $lineN | cut -d ":" -f 3)
   DST_PORT=$(echo $lineN | cut -d ":" -f 4)
   DST_DIR0=$(echo $lineN | cut -d ":" -f 5)
   # Avoid problems. Always append "/" to the end for dirs
   if [[ $DST_DIR0 != */ ]] ; then DST_DIR0="${DST_DIR0}/" ; fi
   RSYNC_EXTRA_DIR_OPTS=""
   if [ -f ${SRC}easyup.conf ] ; then
       source ${SRC}easyup.conf
   fi
   if [ -f ${SRC}easyup.sh ] ; then
       bash -x ${SRC}easyup.sh 1>${SRC}easyup.sh.log 2>&1
   fi
   if [[ -f ${SRC} || -d ${SRC} ]] ; then
       if [[ -d ${SRC} ]] ; then
           echo $DATE > ${SRC}/easyup.last_backup_date
       else
           echo $DATE > ${SRC}.easyup.last_backup_date
       fi
       SRC_REFER0=`echo -n ${DST_DIR0}                                                 `
       SRC_REFERA=`echo -n ${DST_DIR0} ; echo ${SRC}${REFERA_POSTFIX} | sed "s/[/]/_/g"`
       # It could be the case that SRC_REFERA is a symlink to a symlink to a symlink ...
       # Use original (non-symlink) backup reference
       REMOTE_SCRIPT="readlink -f ${SRC_REFER0}"
       SRC_REFER0=$(ssh -T -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" )
       REMOTE_SCRIPT="readlink -f ${SRC_REFERA}"
       SRC_REFERA=$(ssh -T -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" )
       SRC_TARGET=`echo -n ${DST_DIR0} ; echo ${SRC}${TARGET_POSTFIX} | sed "s/[/]/_/g"`
       RSYNC_FULL_OPTS="${RSYNC_DEFAULT_OPTS} ${RSYNC_EXTRA_DIR_OPTS} "
       if [ -n ${SRC_REFER0} ]; then
           RSYNC_FULL_OPTS="${RSYNC_FULL_OPTS} --link-dest ${SRC_REFER0} "
       fi
       if [ -n ${SRC_REFERA} ]; then
           RSYNC_FULL_OPTS="${RSYNC_FULL_OPTS} --link-dest ${SRC_REFERA} "
       fi
       if [[ $DRYRUN == true ]] ; then
         cat << _________EOF
dry-run:
- CURRENT WORKING DIR: $(pwd)
- planned execution:
rsync -e "ssh -T -p ${DST_PORT}" ${RSYNC_FULL_OPTS} ${SRC} ${DST_USER}@${DST_HOST}:${SRC_TARGET}  || echo -n ""
_________EOF
       else
         rsync -e "ssh -T -p ${DST_PORT}" ${RSYNC_FULL_OPTS} ${SRC} ${DST_USER}@${DST_HOST}:${SRC_TARGET}  || echo -n ""
         # Create sym link if ssh skips backup (no modifications found)
         REMOTE_SCRIPT="if [[ ! -f $SRC_TARGET && ! -d $SRC_TARGET ]] ; then ln -s ${SRC_REFERA} ${SRC_TARGET} ; fi"
         ( ssh -T -p ${DST_PORT} ${DST_USER}@${DST_HOST} "${REMOTE_SCRIPT}" ) &
       fi
   else
       echo "failed $SRC copy due to: ${SRC} must be a file or directory"
   fi
   echo "debug: $lineN end ${ERROR}"
done
echo -n "end: " ; date
