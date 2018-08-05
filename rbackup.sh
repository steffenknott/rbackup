#!/bin/bash

set -e
set -x

#
# Complete copy of filesystem to given directory
#

RSYNC=/usr/bin/rsync
BASE_DIRECTORY=/daten/kunden

if [ "$1" = "" ]
then
 echo "Usage: $0 <job_name> <day> <month>" # full|diff|yesterday|<day>"
 exit 1
fi

if [ ! -d "$BASE_DIRECTORY" ];
then
 echo "FATAL: BASE_DIRECTORY not found. Check setting in script."
 exit 1
fi

if [ "$2" = "full" ];
then
 echo "FULL backup forced."
 ACTION="FULL"
fi

if [ "$2" = "diff" ];
then
 echo "DIFF backup forced."
 ACTION="DIFF"
fi

if [ "$2" = "yesterday" ];
then
 echo "Backup for yesterday forced."
 ACTION="DIFF"
 OFFSET=-1
fi

CMDDAY=$2
CMDMONTH=$3

JOB_NAME=$1
REMOTE_PATH=/
# reading backup job config from settings file
# we need REMOTE_HOST, REMOTE_PORT, BACKUP_DIR,

source ${BASE_DIRECTORY}/${JOB_NAME}.conf

EXCLUDE_FILE=${BACKUP_DIR}/excludes.conf
INCLUDE_FILE=${BACKUP_DIR}/includes.conf

TEMPDIR=/tmp
LOGFILE=${TEMPDIR}/${JOB_NAME}.log
TO_MAIL="sk@edv-knott.de"
FROM_MAIL="srvbackup01@sysop.edv-knott.de"

# get current full and daily backup directory

#DAYOFMONTH=`date "+%d"`
#DAYOFMONTH=$((DAYOFMONTH+OFFSET))
DAYOFMONTH=$CMDDAY
#MONTHNUMBER=`date "+%-m"`
MONTHNUMBER=$CMDMONTH

STARTTIME=`date`
STARTSECS=`date +%s`

if [ $(( ${MONTHNUMBER} % 2 )) = 0 ];
then
 FULL_DIR=${BACKUP_DIR}/even.full
 DAILY_DIR=${BACKUP_DIR}/even.daily.${DAYOFMONTH}
else
 FULL_DIR=${BACKUP_DIR}/odd.full
 DAILY_DIR=${BACKUP_DIR}/odd.daily.${DAYOFMONTH}
fi

# deciding what to do
if [ "$ACTION" = "" ]; then
  if [ ! -d "$FULL_DIR" ]; then
   echo "Will do FULL backup for >${JOB_NAME}< (active full backup dir not found) " > ${LOGFILE}
   ACTION="FULL"
  else
   if [ "$DAYOFMONTH" = "01" ]; then
     echo "Will do FULL backup for >${JOB_NAME}< (full backup dir found but first day of month) " > ${LOGFILE}
     ACTION="FULL"
   else
     echo "Will do DIFF backup for >${JOB_NAME}< (full backup dir found and not the first day of month) " > ${LOGFILE}
     ACTION="DIFF"
   fi
  fi
fi

# safety checks

if [ "$FULL_DIR" = "" ]; then
  echo "CRITICAL: FULL DIR IS EMPTY!" > ${LOGFILE}
  exit
fi

if [ "$DAILY_DIR" = "" ]; then
  echo "CRITICAL: DAILY DIR IS EMPTY!" > ${LOGFILE}
  exit
fi

# run backup

if [ "$ACTION" = "FULL" ]; then
  # run full backup
  echo "Full Rsync Backup for >${JOB_NAME}< on " `date` > ${LOGFILE}
  $RSYNC -avxzc -e "ssh -p ${REMOTE_PORT}" --numeric-ids --delete --log-file=${LOGFILE} \
         --exclude-from=${EXCLUDE_FILE} root@${REMOTE_HOST}:${REMOTE_PATH} ${FULL_DIR}/ >/dev/null
  touch ${FULL_DIR}
  # cleaning up empty directories
  find ${FULL_DIR} -depth -type d -empty -delete
else
  # run differential backup and touching dir to save backup date/time
  echo "Differential Rsync Backup for >${JOB_NAME}< on " `date` > ${LOGFILE}
  $RSYNC -avxzc -e "ssh -p ${REMOTE_PORT}" --numeric-ids --log-file=${LOGFILE} --compare-dest=${FULL_DIR} \
         --exclude-from=${EXCLUDE_FILE} root@${REMOTE_HOST}:${REMOTE_PATH} ${DAILY_DIR}/ >/dev/null
  touch ${DAILY_DIR}
  # cleaning up empty directories
  find ${DAILY_DIR} -depth -type d -empty -delete
fi

ENDTIME=`date`
ENDSECS=`date +%s`

# check return code
#  0 = success,
# 24 = ok, just some files changed during backup
# else = error (see: man (1) rsync)
if ! [ $? = 24 -o $? = 0 ] ; then
 echo "" >> ${LOGFILE}
 echo "Fatal: rsync finished >${JOB_NAME}< with errors!" >> ${LOGFILE}
fi

# finished
RUNTIME=$((ENDSECS-STARTSECS))
echo "" >> ${LOGFILE}
echo "Finished rsync backup of >${JOB_NAME}< on " `date` >> ${LOGFILE}
echo "${STARTTIME};${ENDTIME};${RUNTIME};${JOB_NAME}" >> /root/backup_timing.log

# to be sure
sync

# mail report
#sendmail "${MAIL_ADDRESS}" < ${MAIL}
mail -r ${FROM_MAIL} -s "Log of Rsync Backup >${JOB_NAME}<" ${TO_MAIL} < ${LOGFILE}

# clean up
#rm ${LOGFILE}
