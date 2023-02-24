#!/bin/bash 
#
# Brainbackup
# 
# Author: Christophe Casalegno / Brain 0verride
# Contact: brain@christophe-casalegno.com
# Version 1.1
#
# Copyright (c) 2021 Christophe Casalegno
#
# This program is free software: you can redistribute it and/or modify
#
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>
#
# The license is available on this server here:
# https://www.christophe-casalegno.com/licences/gpl-3.0.txt
#
# brainbackup.cfg format
# ROOTSCRIPT:/home/brain # Where is your script
# MYSQL_BACKUP_USER:backup # Your MySQL / MariaDB backup user 
# MYSQL_USER_PASS:mypassword # Your MySQL / MariaDB backup user password
# MYSQL_LOCAL_ROOT:/home/brainbackup # Where you want to do local MySQL / MariaDB backups
# MYSQL_LOCAL_RETENTION:4 # Local MySQL / MariaDB backup retention
# MYSQL_DB_LIST:mysql.txt # The name of the file that contain MySQL / MariaDB databases list (no need to change)
# BACKUP_DIR_LIST:dir.txt # The name of the file that contain directory to backup (no need to change)
# BACKUP_SERVER_NAME:backup.christophe-casalegno.com # Hostname of your backup server
# BACKUP_SERVER_ROOT:/datastore/customers # Root directory of the backup place on backup server
# BACKUP_SERVER_DST:brain # user/directory on the backup server
# DIR_REMOTE_RETENTION:30D # Remote retention on backup server in days



CONF_FILE="brainbackup.cfg"

function read_config()
{
	CONF_FILE="$1"
	VAR_CONF=$(cat $CONF_FILE)

	for LINE in $VAR_CONF
	do
		VARNAME1=${LINE%%:*}
		VARNAME2=${VARNAME1^^}
		VAR=${LINE#*:}
		eval ${VARNAME2}=$VAR
	done
}

read_config $CONF_FILE

BACKUP_COMMAND='rdiff-backup'

# Bases de données (MySQL / MariaDB) 

function formatandlog()
{
	INTROFORMAT="$1"
	TARGETFORMAT="$2"
	CHAIN2FORMAT="$3"
	GREEN="\e[32m"
	YELLOW="\e[33m"
	RED="\e[31m"
	ENDCOLOR="\e[0m"

	if [[ "${TARGETFORMAT}" = 'N' ]]
	then
		echo "${INTROFORMAT} ${CHAIN2FORMAT}"
	
	elif [[ "${TARGETFORMAT}" = 'O' ]]
	then
		echo -e "${INTROFORMAT} ${GREEN}${CHAIN2FORMAT}${ENDCOLOR}"
	
	elif [[ "${TARGETFORMAT}" = 'W' ]]
	then
		echo -e "${INTROFORMAT} ${YELLOW}${CHAIN2FORMAT}${ENDCOLOR}"
	
	elif [[ "${TARGETFORMAT}" = 'E' ]]
	then
		echo -e "${INTROFORMAT} ${RED}${CHAIN2FORMAT}${ENDCOLOR}"
		
	else
		echo 'format not specified'
	fi
}

function checktest()
{
	if [ "$2" -eq 0 ]

		then
			formatandlog $1 O "OK"
		else
			formatandlog $1 E "ERROR"
	fi
}

function mysql_local_backupdir() 
{

	MYSQL_LOCAL_ROOT="$1"
	MY_DATE=$(date +"%y-%m-%d-%H")
	
	if [[ ! -e "$MYSQL_LOCAL_ROOT" ]]
	then
		echo "$MYSQL_LOCAL_ROOT doesn't exist"
		mkdir "$MYSQL_LOCAL_ROOT"
	else
		if [[ ! -d "$MYSQL_LOCAL_ROOT" ]]
		then
			echo "$MYSQL_LOCAL_ROOT is a file"
			exit 1
		else
			echo "$MYSQL_LOCAL_ROOT is a directory"
		fi
	fi

	
	mkdir "$MYSQL_LOCAL_ROOT"/"$MY_DATE"
	mkdir "$MYSQL_LOCAL_ROOT"/"$MY_DATE"/logs
}


function mysql_backup_list() 
{

	declare -A sqlfilter

	MYSQL_FILTER_FILE="mysqlfilter.cfg"

	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	MYSQL_BACKUP_USER="$3"
	MYSQL_USER_PASS="$4"

	if [[ -s "$MYSQL_FILTER_FILE" ]]

	then
		echo "File exists and is filled"

		SQL_FILTER=$(cat $MYSQL_FILTER_FILE)

		for FILTER in $SQL_FILTER
		do
			sqlfilter["$FILTER"]=$(echo "\|$FILTER")
		done

		FILTER_COMMAND="grep -v -w "
		FILTER_ARGS=$(echo ${sqlfilter[@]}|sed s"/ //g")
		mysqlshow -u "$MYSQL_BACKUP_USER" -p"$MYSQL_USER_PASS" |cut -d " " -f2 |grep [a-z\|A-Z\|0-9] | $FILTER_COMMAND $FILTER_ARGS >/$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST
		checktest "mysqlshow" "$?"
	else
		echo "File doesn't exist or empty"
		mysqlshow -u"$MYSQL_BACKUP_USER" -p"$MYSQL_USER_PASS" |cut -d " " -f2 |grep [a-z\|A-Z\|0-9] >/$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST
		checktest "mysqlshow" "$?"
	fi

} 

function mysql_backup() 

{
	COMPRESSOR="pigz"
	MY_DATE=$(date +"%y-%m-%d-%H")
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	MYSQLDUMP_OPTIONS="--dump-date --no-autocommit --single-transaction --hex-blob --triggers -R -E"

	while read DB_NAME
	do
		echo "Dumping $DB_NAME..."
		mysqldump -u"$MYSQL_BACKUP_USER" -p"$MYSQL_USER_PASS" "$DB_NAME" $MYSQLDUMP_OPTIONS \
			| "$COMPRESSOR" > $MYSQL_LOCAL_ROOT/$MY_DATE/$DB_NAME-$MY_DATE.sql.gz \
			2>>$MYSQL_LOCAL_ROOT/$MY_DATE/logs/$DB_NAME-$MY_DATE-error.log
		checktest "mysqldump_$DB_NAME" "$?"
	done < /"$MYSQL_LOCAL_ROOT"/"$MYSQL_DB_LIST"
} 


function mysql_purge_old_backup() {

	MYSQL_LOCAL_ROOT="$1"
	MYSQL_LOCAL_RETENTION="$2"

	if [ ! -d "$MYSQL_LOCAL_ROOT" ]
	then
		exit 0
	else
		find "$MYSQL_LOCAL_ROOT" -mtime +"$MYSQL_LOCAL_RETENTION" -exec rm -rf {} \;
		checktest "mysqlpurge" "$?"
	fi


} 


function do_mysql_backup()
{
	MYSQL_LOCAL_ROOT=$1
	MYSQL_DB_LIST=$2
	MYSQL_LOCAL_RETENTION=$3
	
	mysql_local_backupdir $MYSQL_LOCAL_ROOT
	mysql_backup_list $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST $MYSQL_BACKUP_USER $MYSQL_USER_PASS
	mysql_backup $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST 
	mysql_purge_old_backup $MYSQL_LOCAL_ROOT $MYSQL_LOCAL_RETENTION

} 


# Fichiers et répertoires

function dir_backup_list() 
{
	ROOTSCRIPT="$1"
	BACKUP_DIR_LIST="$2"
	FILTER="./,dev,lost+found,media,mnt,opt,proc,run,srv,sys" # directories you don't wants to backup
	REAL_FILTER=$(echo "$FILTER" |sed 's#,#\\|#g')
	ls / -par -- |sort |grep / |grep -v -w $REAL_FILTER |cut -d "/" -f1 > /"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"
	checktest "dir_backup_list" "$?"
}


function dir_remote_backup()
{
	BACKUP_SERVER_DST="$1"
	BACKUP_SERVER_NAME="$2"
	BACKUP_SERVER_ROOT="$3"
	BACKUP_DIR_LIST="$4"
	BACKUP_COMMAND="$5"

	while read dir2backup
	do
		echo "Backuping $dir2backup..."
		$BACKUP_COMMAND /"$dir2backup" "$BACKUP_SERVER_DST"@"$BACKUP_SERVER_NAME"::"$BACKUP_SERVER_ROOT/$BACKUP_SERVER_DST"/"$dir2backup"
		checktest "rdiff_backup_$dir2backup" "$?"

	done < /"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"
} 


function dir_remote_purge()
{
	BACKUP_SERVER_DST="$1"
	BACKUP_SERVER_NAME="$2"
	BACKUP_SERVER_ROOT="$3"
	BACKUP_DIR_LIST="$4"
	DIR_REMOTE_RETENTION="$5"
	BACKUP_COMMAND="$6"
	PURGE_OPTIONS="--force --remove-older-than"

	while read dir2backup
	do
		echo "Cleaning $dir2backup..."
		$BACKUP_COMMAND $PURGE_OPTIONS "$DIR_REMOTE_RETENTION" "$BACKUP_SERVER_DST"@"$BACKUP_SERVER_NAME"::/"$BACKUP_SERVER_ROOT/$BACKUP_SERVER_DST"/"$dir2backup"
		checktest "rdiff-backup_clean_$dir2backup" "$?"
	done < /"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"

} 

function do_dir_backup()
{
	ROOTSCRIPT="$1"
	BACKUP_DIR_LIST="$2"
	BACKUP_SERVER_DST="$3"
	BACKUP_SERVER_NAME="$4"
	BACKUP_SERVER_ROOT="$5"
	BACKUP_COMMAND="$6"
	DIR_REMOTE_RETENTION="$7"
	
	dir_backup_list "$ROOTSCRIPT" "$BACKUP_DIR_LIST"
	dir_remote_backup "$BACKUP_SERVER_DST" "$BACKUP_SERVER_NAME" "$BACKUP_SERVER_ROOT" "$BACKUP_DIR_LIST" "$BACKUP_COMMAND"
	dir_remote_purge "$BACKUP_SERVER_DST" "$BACKUP_SERVER_NAME" "$BACKUP_SERVER_ROOT" "$BACKUP_DIR_LIST" "$DIR_REMOTE_RETENTION" "$BACKUP_COMMAND"
}


do_mysql_backup $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST $MYSQL_LOCAL_RETENTION
do_dir_backup "$ROOTSCRIPT" "$BACKUP_DIR_LIST" "$BACKUP_SERVER_DST" "$BACKUP_SERVER_NAME" "$BACKUP_SERVER_ROOT" "$BACKUP_COMMAND" "$DIR_REMOTE_RETENTION"
