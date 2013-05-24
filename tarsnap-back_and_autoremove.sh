#!/usr/bin/env bash
set -e

# 'tarsnap-back' ; An automated tarsnap backup & auto-purge script
#
# Copyright (c) 2011, Eric Andrew Bixler
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY Eric Andrew Bixler ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL Eric Andrew Bixler BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#        if [ "$query_root" = "root_default=\"y"\" ] ; then #[ -e $conf ] &&
#                sudo `which bash` $(basename "$0")
#                exit 0
#        fi


USERNAME="`id -un`"
tarsnap="`which tarsnap`"
conf="/etc/tarsnap-backup.conf"
deps="chmod chown nice mktemp fgrep nl cat sort tac tail grep awk rm nice wc"
#query_root=$(grep "root_default=\"y"\" $conf)


### Trap keyboard interrupt & remove temporary files
trap ctrl_c 2

ctrl_c ()
{
rm -f $archives >> /dev/null 2>&1
rm -f $archives_sorted >> /dev/null 2>&1
rm -f $stats >> /dev/null 2>&1
echo -ne "\n\n"
echo -ne "Interrupt SIGINT caught"
echo -ne "\nTemporary files removed\n"
echo -ne "\nBye !\n"
exit 1
}

        echo ""
        echo "Validating Environment..."
	echo ""
sleep 1

### Check for required dependencies

	echo "==> Checking Dependencies"

for i in "$deps" ; do
	which $(echo $i) > /dev/null &&
	if [ "$?" -ne "0" ] ; then
		echo "==| Error: Required dependency could not be found:" $i
		echo ""
		echo "Please correct the problem, and rerun the script"
		echo "Exiting."
		exit 1
	else
		echo -n "    Dependencies: " && sleep 1 && echo "  [ OK ]"
        fi
done

### Check for root privelages

if [ "${USERNAME}" != "root" ] ; then
        echo ""
        echo "==> Checking Permissions"
        echo -n "    Root: " && sleep 1 && echo "[ NO ]"
	echo ""
	echo ""
	echo "-------------------------------------------------------------------"
	echo ""
	echo ""
	echo "You are using an un-privileged (non root) user account."
        echo "While it is recommended to run this as root it is not required,"
        echo "however if you continue as '${USERNAME}' Tarsnap will only be able to"
	echo "backup files/folders that your user has adequate permissions to read."
        echo ""
        echo "If you would you like to switch users and run as root, press (y)"
	echo "You will be prompted for your password, and return to the current process."
	echo "If would you like to continue as the current user '${USERNAME}', then press (n)"
        read -p "==| " yn
	###
        if [ "$yn" != "y" ] && [ "$yn" != "n" ] && [ "$yn" != "yes" ] && [ "$yn" != "no" ] ; then
                echo ""
                echo "Unrecognized Input."
                echo "Please answer (y/n)"
                echo "Exiting."
                echo ""
                exit 1
        fi
	###
	echo ""
	if [ "$yn" == "y" ] ; then
                echo "==> Switching to [ root ]"
		### Return the process as root
                echo -n "    " && su -c "`which bash` $(basename "$0")"
                exit 0
        else
		echo ""
                echo "==> Continuing as current user '${USERNAME}'"
        fi
else
	sleep 1
	echo ""
	echo "==> Checking Permissions"
        echo -n "    Root: " && sleep 1 && echo "          [ OK ]"
        sleep 2
fi


### Check for an existing config file, and create one if it doesn't exist

if [ -f $conf ] ; then
	. $conf
else
	echo ""
	echo ""
	echo "-------------------------"
	echo ""
	echo "* No config file found! *"
	echo "* Starting config setup *"
	echo ""
	echo "-------------------------"
	echo ""
	echo "How many versions should Tarsnap should keep: "
	read -p "==| " versions
	if [ $versions -lt "1" ] ; then
		echo ""
		echo "This number must be greater then zero"
		echo "Exiting."
		exit 1
	fi
	echo ""
	###
	echo "How many times a day will this backup run: "
        read -p "==| " times_a_day
	if [ $times_a_day -lt "1" ] ; then
		echo ""
		echo "This number must be greater then zero"
		echo "Exiting."
		exit 1
	fi
	echo ""
	###
	echo "What files and/or folders should be included: "
	echo "This is a space-separated list, relative to /"
	echo "Please include the full path"
	echo "Ex: etc bin root srv opt"
	read -p "==| " backuptargets
	if [ -z "$backuptargets" ] ; then
		echo "You have not entered any destination(s)"
		echo "Exiting."
		exit 1
	fi
	echo ""
	###
	echo "Where is your tarsnap keyfile located ?"
	read -p "==| " keyfile
        if [ -z "$keyfile" ] ; then
                echo "You have not entered any destination(s)"
                echo "Exiting."
                exit 1
	fi
	echo ""
	###
	echo "Where do you want the Tarsnap cache directory located ?"
	echo "(The default cache directory location is /usr/local/tarsnap-cache)"
	read -p "==| " cachedir
        if [ -z "$cachedir" ] ; then
                echo "You have not entered any destination(s)"
                echo "Exiting."
                exit 1
        fi
	echo ""

###
#
# Not working yet
#
#	echo "Would you like to run as 'root' by default in the future ? (y/n) "
#        read -p "==| " def_root
#        if [ "$def_root" != "y" ] && [ "$yn" != "n" ] ; then
#                echo ""
#                echo "Unrecognized Input."
#                echo "Please answer (y/n) only."
#                echo "Exiting."
#                echo ""
#                exit 1
#	fi
#	echo ""

### Some calculations to write to the config.

	items_to_backup="`echo $backuptargets | wc -w | awk '{print $1}'`"
	c2="$((($versions*$items_to_backup)+1))"

### Write the config to /etc, and give it proper permissions

	touch /etc/tarsnap-backup.conf
	chmod 755 /etc/tarsnap-backup.conf
	chown $USERNAME:$USERNAME /etc/tarsnap-backup.conf
	###
	echo "#  The number of versions to keep." > /etc/tarsnap-backup.conf
	echo "#  this number is calculated with this formula: ((versions * items)+1)" > /etc/tarsnap-backup.conf
	echo "#  if you need to change the number of versions either; delete this config file, or plug-in your new requirements to:  ((versions * items)+1)"  >> /etc/tarsnap-backup.conf
	echo "n=\"$c2\"" >> /etc/tarsnap-backup.conf
	echo " " >> /etc/tarsnap-backup.conf
	###
	echo "#  How many times a day the backup is set to run" >> /etc/tarsnap-backup.conf
	echo "times=\"$times_a_day\"" >> /etc/tarsnap-backup.conf
	echo " " >> /etc/tarsnap-backup.conf
	###
	echo "#  The number of files/folders that are being backed-up. do not edit this number manually." >> /etc/tarsnap-backup.conf
	echo "#  (if you need to change The number of files/folders, *delete* this config file and re-run tarsnap-back_and_autoremove)"  >> /etc/tarsnap-backup.conf
	echo "items_to_backup=\"$items_to_backup\"" >> /etc/tarsnap-backup.conf
	echo " " >> /etc/tarsnap-backup.conf
	###
	echo "#  This is a space-separated list of directories to backup; relative to /" >> /etc/tarsnap-backup.conf
	echo "backuptargets=\"$backuptargets\"" >> /etc/tarsnap-backup.conf
        echo " " >> /etc/tarsnap-backup.conf
	###
	echo "#  This is the location of the cryptographic keys used to encrypt and sign the machine's backups you created" >> /etc/tarsnap-backup.conf
	echo "keyfile=\"$keyfile\"" >> /etc/tarsnap-backup.conf
        echo " " >> /etc/tarsnap-backup.conf
	###
	echo "#  Tarsnap cache directory. See tarsnap MAN" >> /etc/tarsnap-backup.conf
	echo "cachedir=\"$cachedir\"" >> /etc/tarsnap-backup.conf
        echo " " >> /etc/tarsnap-backup.conf

	###
#	echo "#  Run as 'root' by default ?" >> /etc/tarsnap-backup.conf
#	echo "#  note: *do not* change this vale to 'n'. if your intent is to reset its default behavior" >> /etc/tarsnap-backup.conf
#	echo "#  root by default; then completley remove the line below." >> /etc/tarsnap-backup.conf
#	echo "root_default=\"$def_root\"" >> /etc/tarsnap-backup.conf
	###

	echo "A config file has been created here: $conf"
	echo "Please *DO NOT* edit this file manually."
	echo "Check the comments in the config if you need to change any values."
	echo "Or you can delete the current config file located at $conf to rerun setup"
	source $conf
fi

### Variables (dont edit these)

no_vers=$(($n-1))
vers=$(($no_vers/$items_to_backup))

### Print some info about your current config

echo ""
echo ""
echo "-------------------------------------------------------------------"
echo ""
echo "Number of versions set to keep  ==|" "[ $vers ]"
echo -n "Files/Folders set to backup     ==|" "[ $items_to_backup ]"  && echo " [ $backuptargets ]"
echo "Path to Config                  ==|" "[ $conf ]"
echo "Path to Tarsnap Cache           ==|" "[ $cachedir ]"
echo "Path to Tarsnap Keyfile         ==|" "[ $keyfile ]"
echo ""
echo "-------------------------------------------------------------------"
echo ""
echo ""
echo ""

sleep 2
echo "==> Checking for an Existing Cache Directory"
echo "--------------------------------------------"
if [ -d /usr/local/tarsnap-cache ] ;
then
        echo "==> Cache Already Exists"
        echo "==> Continuing..."
else
        echo "==> Cache Doesn't Exist"
        echo "==> Creating @ $cachedir"
        mkdir /usr/local/tarsnap-cache
fi

### Start the backup

echo ""
echo ""
echo ""
echo "-------------------------------------------------------------------"
echo "                      * Backup Starting Now *                      "
echo "-------------------------------------------------------------------"
echo ""

sleep 1
for dir in $(echo $backuptargets) ; do
	echo ""
	echo "===============|"
	echo "Now Processing | ==> $dir"
	echo "Date Recorded  | ==> `date +%m-%d-%Y_%I:%M:%S`"
	echo "Raw Dir Size   | ==> `du -hs /$dir`"
	echo ""
	echo "Result:"
	$tarsnap --keyfile $keyfile --cachedir $cachedir -c -f $(hostname)-$(date +%m-%d-%Y_%I:%M:%S)-$(echo $dir | tr -d '/') \
	--aggressive-networking --humanize-numbers --quiet --one-file-system /$dir
	echo "==> Complete; No Errors Reported"
done

### More variables

n2=$(($n*$times))
archives=`mktemp`
archives_sorted=`mktemp`
newdata=`mktemp`
stats=`mktemp`

### Decide what archives need to be pruged

$tarsnap --keyfile $keyfile --quiet --list-archives > $archives
cat $archives | sort | tac | tail -n +`echo $n2` > $archives_sorted

### Show volumes queued for deletion. Ask if we should continue with the process.

echo ""
echo ""
echo "--------------------------------"
echo " `cat $archives | sort | fgrep -f $rm $archives_sorted | wc -l` Archives queued for deletion:"
echo "--------------------------------"
cat $archives | fgrep -f $archives_sorted | nl -s "|  " -w 1 && echo -n " "
echo ""
echo "Continue ? (y/n)"
read -p "==| " cont
if [ "$cont" = "y" ] ; then
                echo ""
       fi
if [ "$cont" = "n" ] ; then
		echo ""
		echo "User aborted process."
		echo "Nothing was deleted"
                echo "Exiting Now."
		echo ""
		exit 1
       fi
if [ "$cont" != "y" ] && [ "$yn" != "n" ] ; then
                echo ""
                echo "Unrecognized Input."
                echo "Please answer (y/n) only."
                echo "Exiting."
                echo ""
                exit 1
       fi

### Purge old archives

echo ""
echo "-------------------------------------------------------------------"
echo "            * Removing Versions Queued for Deletion *              "
echo "-------------------------------------------------------------------"
echo ""

sleep 2
cat $archives | fgrep -f $archives_sorted | while read archive ; do
	echo ""
	echo "==> Deleting: $archive"
	$tarsnap --keyfile $keyfile --cachedir $cachedir -d -f $archive --humanize-numbers
	echo "==> Complete"
done

### Print some statistics about the backup/purge process, and the data currently stored with tarsnap/S3

echo ""
echo ""
echo "-------------------------------------------------------------------"
echo "                         * Statistics *                            "
echo "-------------------------------------------------------------------"
echo ""
echo ""
echo " |   [ `cat $archives | sort | fgrep -f $rm $archives_sorted | wc -l` ] Deleted Archives"
echo "-|-------------------------"
cat $archives | sort | fgrep -f $archives_sorted | nl -s "|   " -w 1 && echo -n " "

if [ "$?" -eq "1" ] ; then
	echo ""
	echo "No Old Versions are Marked for Deletion."
	echo ""
	echo "Backup Complete!"
	echo "Exiting Now."
else
	echo ""
	echo ""
	$tarsnap --keyfile $keyfile --cachedir $cachedir --print-stats --humanize-numbers > $stats
	echo "All Data"
	echo "--------"
	echo -n "Uncompressed:            " && echo -n "[ `cat $stats | grep "All archives" | awk '{print $3,$4}'` ]"
	echo ""
	echo -n "Compressed:              " && echo -n "[ `cat $stats | grep "All archives" | awk '{print $5,$6}'` ]"
	echo " "
	echo ""
	echo "Unique Data"
	echo "-----------"
	echo -n "In All Archives:         " && echo -n "[ `cat $stats | grep "unique data" | awk '{print $3,$4}'` ]"
	echo " "
	echo ""
	echo "Remote Payload"
	echo "---------------------"
	echo -n "Final Total:             " && echo -n "[ `cat $stats | grep "unique data" | awk '{print $5,$6}'` ]"
	echo ""
	echo ""
	echo ""
	echo "==> Completed; Exiting Now."
	echo ""
fi

### Clean-up

rm -f $archives
rm -f $archives_sorted
rm -f $stats

### Bye !

exit 0
