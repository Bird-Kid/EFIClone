#!/bin/bash
# EFI Partition Clone Script
# Created by Ted Howe (c) 2018 | tedhowe@burke-howe.com | wombat94 on GitHub   | wombat94 on TonyMacx86
# Modified by kobaltcore 2019  | cobaltcore@yandex.com  | kobaltkore on GitHub | byteminer on TonyMacx86
# Modified by Bird-Kid 2020    |                        | Bird-Kid on GitHub   | Bird-Kid on TonyMacx86

# This script is designed to be a "post-flight" script run automatically by CCC at the end of a
# clone task. It will copy the contents of the source drive's EFI partition to the destination drive's EFI
# partition. It will COMPLETELY DELETE and replace all data on the destination EFI partition.

# THIS SCRIPT MODIFIES DATA AND AS SUCH CAN CAUSE DATA LOSS!
# Use this at your own risk. We've tried to make it as safe as possible, but nobody's perfect.


### START USER VARIABLES ###

# Whether to run in LIVE or DEBUG mode. If this is "Y", this script will operate in dry-run mode, simply logging
# what it would do without actually doing it.
# Setting this to any other values (preferably "N") will switch to live mode, in which the operations will be executed.
TEST_SWITCH="Y"

# The location of the log file. Since the root partition is read-only in Catalina and higher
# we write to the "Shared" folder instead.
LOG_FILE="/Users/Shared/EFIClone.log"

### END USER VARIABLES ###


source utils.sh

if [[ -f "$LOG_FILE" ]]; then
	rm $LOG_FILE
fi

writeTolog 'Starting EFI Clone Script...'
writeTolog "Running $0..."

# Determine which disk clone application called the script (based on number of parameters)
# - log details
# - set up initial parameters
# - if possible do app-specific sanity checks in order to exit without taking action if necessary
if [[ "$#" == "2" ]]; then
	writeTolog 'Running in "Shell" mode:'
	writeTolog "1: Source Path = $1"
	writeTolog "2: Destination Path = $2"

	sourceVolume=$1
	destinationVolume=$2
elif [[ "$#" == "4" ]]; then
	writeTolog 'Running in "Carbon Copy Cloner" mode:'
	writeTolog "1: Source Path = $1"
	writeTolog "2: Destination Path = $2"
	writeTolog "3: CCC Exit Status = $3"
	writeTolog "4: Disk image file path = $4"

	if [[ "$3" == "0" ]]; then
		writeTolog 'Check passed: CCC completed with success.'
	else
		failGracefully 'CCC did not exit with success.' 'CCC task failed.'
	fi

	if [[ "$4" == "" ]]; then
		writeTolog "Check passed: CCC clone was not to a disk image."
	else
		failGracefully 'CCC clone destination was a disk image file.' 'CCC disk image clone destinations are not supported.'
	fi

	sourceVolume=$1
	destinationVolume=$2
elif [[ "$#" == "6" ]]; then
	writeTolog 'Running in "SuperDuper" mode:'
	writeTolog "1: Source Disk Name = $1"
	writeTolog "2: Source Mount Path = $2"
	writeTolog "3: Destination Disk Name = $3"
	writeTolog "4: Destination Mount Path = $4"
	writeTolog "5: SuperDuper! Backup Script Used = $5"
	writeTolog "6: Unused parameter 6 = $6"

	sourceVolume=$2
	destinationVolume=$4
else
	echo "Parameter count of $# is not supported."
	failGracefully "Parameter count of $# is not supported." 'Unsupported set of parameters received.'
fi


### Figure out source target ###

writeTolog "sourceVolume = $sourceVolume"

sourceVolumeDisk="$( getDiskNumber "$sourceVolume" )"

# If we can't figure out the path, we're probably running on Mojave or later, where CCC creates a temporary mount point
# We use the help of "df" to output the volume of that mount point, afterwards it's business as usual
if [[ "$sourceVolumeDisk" == "" ]]; then
	sourceVolume=$( df "$sourceVolume" | grep /dev | cut -d ' ' -f 1 | cut -d '@' -f 2 )
	sourceVolumeDisk="$( getDiskNumber "$sourceVolume" )"
fi

# If it's still empty, we got passed an invalid path, so we exit
if [[ "$sourceVolumeDisk" == "" ]]; then
	failGracefully 'Source Volume Disk not found.'
fi

writeTolog "sourceVolumeDisk = $sourceVolumeDisk"

sourceEFIPartition="$( getEFIPartition "$sourceVolumeDisk" )"
writeTolog "sourceEFIPartition = $sourceEFIPartition"


### Figure out destination target ###

writeTolog "destinationVolume = $destinationVolume"

destinationVolumeDisk="$( getDiskNumber "$destinationVolume" )"

writeTolog "destinationVolumeDisk = $destinationVolumeDisk"

destinationEFIPartition="$( getEFIPartition "$destinationVolumeDisk" )"
writeTolog "destinationEFIPartition = $destinationEFIPartition"


### Sanity checks ###

if [[ "$sourceEFIPartition" == "" ]]; then
	failGracefully 'EFI source partition not found.'
fi

if [[ "$destinationEFIPartition" == "" ]]; then
	failGracefully 'EFI destination partition not found.'
fi

if [[ "$sourceEFIPartition" == "$destinationEFIPartition" ]]; then
	failGracefully 'EFI source and destination partitions are the same.'
fi

sourceEFIPartitionSplit=($sourceEFIPartition)
if [ "${#sourceEFIPartitionSplit[@]}" -gt 1 ]; then
	failGracefully 'Multiple EFI source partitions found.'
fi

destinationEFIPartitionSplit=($destinationEFIPartition)
if [ "${#destinationEFIPartitionSplit[@]}" -gt 1 ]; then
	failGracefully 'Multiple EFI destination partitions found.'
fi

### Mount the targets ###

diskutil quiet mount readOnly /dev/$sourceEFIPartition
if (( $? != 0 )); then
	failGracefully 'Mounting EFI source partition failed.'
fi

diskutil quiet mount /dev/$destinationEFIPartition
if (( $? != 0 )); then
	failGracefully 'Mounting EFI destination partition failed.'
fi

writeTolog 'Drives mounted.'
sourceEFIMountPoint="$( getDiskMountPoint "$sourceEFIPartition" )"
writeTolog "sourceEFIMountPoint = $sourceEFIMountPoint"

destinationEFIMountPoint="$( getDiskMountPoint "$destinationEFIPartition" )"
writeTolog "destinationEFIMountPoint = $destinationEFIMountPoint"


### Execute the synchronization ###

if [[ "$TEST_SWITCH" == "Y" ]]; then
	writeTolog 'Simulating file synchronization...'
	writeTolog 'The following rsync command will be executed with the "--dry-run" option:'
	writeTolog "rsync -av --exclude='.*'' \"$sourceEFIMountPoint/\" \"$destinationEFIMountPoint/\""
	writeTolog "THE BELOW OUTPUT IS FROM AN RSYNC DRY RUN! NO DATA HAS BEEN MODIFIED!"
	writeTolog "----------------------------------------"
	rsync --dry-run -av --exclude=".*" --delete "$sourceEFIMountPoint/" "$destinationEFIMountPoint/" >> ${LOG_FILE}
	writeTolog "----------------------------------------"
else
	writeTolog "Synchronizing files from $sourceEFIMountPoint/EFI to $destinationEFIMountPoint..."
	writeTolog "----------------------------------------"
	rsync -av --exclude=".*" --delete "$sourceEFIMountPoint/" "$destinationEFIMountPoint/" >> ${LOG_FILE}
	writeTolog "----------------------------------------"
fi

writeTolog 'Comparing checksums of EFI directories...'
writeTolog "----------------------------------------"
sourceEFIHash="$( collectEFIHash "$sourceEFIMountPoint" )"
destinationEFIHash="$( collectEFIHash "$destinationEFIMountPoint" )"
writeTolog "----------------------------------------"
writeTolog "Source directory hash: $sourceEFIHash."
writeTolog "Destination directory hash: $destinationEFIHash."

diskutil quiet unmount /dev/$destinationEFIPartition
diskutil quiet unmount /dev/$sourceEFIPartition
writeTolog 'EFI partitions unmounted.'

if [[ "$TEST_SWITCH" != "Y" ]]; then
	if [[ "$sourceEFIHash" == "$destinationEFIHash" ]]; then
		writeTolog "Directory hashes match; files copied successfully."
		displayNotification 'EFI Clone Script completed successfully.'
	else
		failGracefully 'Directory hashes differ; copying failed.' 'EFI copied unsuccessfully; files do not match source.'
	fi
fi

writeTolog 'EFI Clone Script completed.'
