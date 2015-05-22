#!/bin/bash
# -*- coding: utf-8; tab-width: 4-*-

#set -e
#set -x

function backupBP {
	# Personal configuration ~ change this
	local user="myuser"					#SSH user for passwordless login
	local postfix=".local.domain.com"			#postfix for the server names
	local servers=(server1 server2)		#servers

	# backup info
	local keep="60 days ago"

	# Static configuration
	local target_dir="/shared"				#BigIP config directory
	local bckp_dir="backups"				#where to store backups
	local bckp_f="conf_backup.ucs"				#temporary backup name
	local bckp_c="backup.conf"				#name of the conf. backup
	local date_format='%Y%m%d%H%M'				#timestamp format


	local scriptdir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
	bckp_dir="$scriptdir/$bckp_dir"

	dirs=(`find "$bckp_dir/" -maxdepth 1 -type d -name "backup_*" | sort`)

	# create (and move) backup directory
	if [ -d "$bckp_dir/" ]; then
		last=$(date --utc -d "$keep" +"$date_format")
		for dir in "${dirs[@]}"; do
			name=$(basename $dir)
			date=$(echo "$name" | grep -o -P '\d{12}')
			date="${date:0:4}-${date:4:2}-${date:6:2} ${date:8:2}:${date:10:2}"
			datecheck=`{ date --utc -d "$date" +"$date_format"; } || { echo ""; }`
			if [ ! -z "$datecheck" ]; then
				if [ "$date" = "-- :" ]; then
					echo "!WARNING: Invalid date format; $name"
				else
					thisdate=`date --utc -d "$date" +"$date_format"`
					if [[ "$thisdate" < "$last" ]]; then
						echo "Removing $name"
						rm -r "$dir"
					fi
				fi
			else
				echo "!WARNING: Invalid backup timestamp: $name"
			fi
		done
	else
		mkdir -p "$bckp_dir/"
	fi

	# get oldest backup; not a symlink & not our current backup
	if [[ ! "${#dirs[@]}" -eq 0 ]]; then
		last_backup="${dirs[-1]}"
		while [[ ! "${#dirs[@]}" -eq 0 ]] && [[ -L "$last_backup" ]] && [[ ! "$last_backup" -eq "backup_$now" ]]; do
			unset $dirs[-1]
			last_backup="${dirs[-1]}"
		done
	fi

	# backup directory for today
	now=`date --utc +"$date_format"`
	echo "This will be backup backup_$now"	

	if [ -d "$bckp_dir/backup_$now" ]; then
		echo "Already have backups for this timestamp. Removing.."
		rm -r "$bckp_dir/backup_$now"
	fi

	mkdir -p "$bckp_dir/backup_$now"
	
	if [ ! -d "$last_backup" ]; then
		echo "!WARNING: Previous backup does not exist. ($last_backup)"
	else
		echo "Comparing to $last_backup"
	fi

	# for every system;
	for servname in "${servers[@]}"; do
		local system=""

		if [[ ! "$servname" == *"."* ]]; then
			system="$servname$postfix"
		else
			system=servname
		fi

		echo "Doing work for $system"
		mkdir -p "$bckp_dir/backup_$now/$system"

		#create full backup
		echo 'Creating backup...'
		ssh "$user@$system" "nice -9 tmsh save /sys ucs $target_dir/$bckp_f"

		#create config backup (additional
		echo 'Creating additional config. backup...'
		ssh "$user@$system" "nice -9 tmsh save /sys config file $target_dir/$bckp_c"

		#copy the backup over
		echo 'Copying files over...'
		scp "$user@$system:$target_dir/$bckp_f" "$bckp_dir/backup_$now/$system/"
		scp "$user@$system:$target_dir/$bckp_c" "$bckp_dir/backup_$now/$system/"
		scp "$user@$system:$target_dir/$bckp_c.tar" "$bckp_dir/backup_$now/$system/"

		#remove the backup file from the remote system
		echo 'Cleaning up...'
		ssh "$user@$system" "rm $target_dir/$bckp_f $target_dir/$bckp_c $target_dir/$bckp_c.tar"

		#show the diff of the configuration file
		if [ ! -z "$last_backup" ]; then
			#if there is something to compare with
			if [ -f "$bckp_dir/backup_$now/$system/$bckp_c" ] && [ -f "$last_backup/$system/$bckp_c" ]; then
				
				#if the backup config exists
				diffed=`diff -I "auth\-password\-encrypted" -I "privacy\-password\-encrypted" "$last_backup/$system/$bckp_c" "$bckp_dir/backup_$now/$system/$bckp_c"`
				
				echo ""
				echo ""
				
				#if there is no difference or we can compare to a previous backup
				if [ -z "$diffed" ]; then
					rm -r "$bckp_dir/backup_$now/"
					last_backup_base=`basename "$last_backup"`
					echo "This backup wasn't necessary as it didn't contain any differences compared to ${last_backup_base}; Symlinked."
					ln -s "$last_backup" "$bckp_dir/backup_$now"
					#we are assuming here the systems are identical, so backups should be the same too.
					#if we have something to compare with, we already have the backup, so no need to duplicate.
					break
				else
					echo "$diffed"
				fi
				
				echo ""
				echo ""
			else
				echo "!WARNING: backup missing; $bckp_dir/backup_$now/$system/$bckp_c"
			fi
		else
			echo 'No backup to compare with, so no diff.'
		fi

		echo '------------------------------------------------------------------------'
	done

	echo 'Finished backing up systems. Use backup.conf to adapt configurations or the UCS for full system backup/restore. (You can rename the UCS to .tar.gz to manually open them up.)'
}

backupBP
