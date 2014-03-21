#!/bin/bash

HERE=$(pwd)
PORT=""
DIR=""
NAME=""
ARGS_OK=0
HOSTS="/etc/hosts"
VHOSTS="/etc/apache2/extra/httpd-vhosts.conf"
UNAME=$(uname)
TS=0

echo "Virtual Host Setup."
echo ""

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# make sure we are running on mac osx :(
if [ $UNAME != "Darwin" ]; then
	echo "This script only works on Mac OS X"
	exit 1
fi

##
# Get a timestamp
function timetamp {
	TS=date +"%Y%m%d%H%M%S"
}

##
# Display help for tool
function usage {
	echo "usage: manage-vhost -n NAME -p PORT -d DIRECTORY"
	echo "-h : this usage message"
	echo "-l : list virtual hosts"
	echo "-n <name> : name of site, i.e. product name"
	echo "-p <port> : port number to access site by"
	echo "-d <path> : top-level directory of website"
	echo "-r <port> : remove virtual host on this port"
	echo "NB: arguments can be given in any order."
	echo ""
	echo "Run with no arguments for interactive mode"
	echo "example: manage-vhost -n mysite -p 9999 -d ~/path/to/site/"
	echo "On completion, the site will be available at localhost:9999"
}

##
# Add virtual host details
# Modifies apache to enable virtual hosts
# Adds details to http-vhosts.conf
# Add details to /etc/hosts
# restarts apache
function addHost {
	# quick check we have everything we need.
	if [ -z $NAME ]; then
		echo "Site name missing!"
		usage
		exit -1;
	else
		NAME="$NAME.site"
	fi

	if [ -z $PORT ]; then
		echo "Site port missing!"
		usage
		exit -1;
	fi

	if [ -z $DIR ]; then
		echo "Site directory missing!"
		usage
		exit -1;
	fi

	#have all parameters, let's make a virtual host!
	echo "Build vhost for $DIR:$PORT as $NAME"

	# enable virtual hosts if not already done so
	if [ ! -f /etc/apache2/httpd.conf.abacus ]; then
		echo "Back up httpd.conf and enable virtual hosts"
		cp /etc/apache2/httpd.conf /etc/apache2/httpd.conf.abacus
		sed -i '' -e "s/#Include \/private\/etc\/apache2\/extra\/httpd-vhosts.conf/Include \/private\/etc\/apache2\/extra\/httpd-vhosts.conf/" /etc/apache2/httpd.conf
	fi

	#Create httpd-vhosts.conf(if necessary)
	if [ ! -f $VHOSTS ]; then
		echo "Create $VHOSTS"
		touch $VHOSTS
	fi

	echo "Append site details to $VHOSTS"
	echo "# Virtual host start $NAME $PORT" >> $VHOSTS
	echo "Listen $PORT" >> $VHOSTS
	echo "NameVirtualHost *:$PORT" >> $VHOSTS
	echo "" >> $VHOSTS
	echo "<Directory \"$DIR\">" >> $VHOSTS
	echo "Allow From All" >> $VHOSTS
	echo "AllowOverride All" >> $VHOSTS
	echo "Options +Indexes" >> $VHOSTS
	echo "</Directory>" >> $VHOSTS
	echo "<VirtualHost *:$PORT>" >> $VHOSTS
	echo "	ServerName \"$NAME\"" >> $VHOSTS
	echo "	DocumentRoot \"$DIR\"" >> $VHOSTS
	echo "</VirtualHost>" >> $VHOSTS
	echo "# Virtual host end $NAME" >> $VHOSTS
	echo "" >> $VHOSTS

	# append details to /etc/hosts

	echo "Append site details to $HOSTS"
	echo "# Virtual host start $NAME $PORT" >> $HOSTS
	echo "127.0.0.1 $NAME" >> $HOSTS
	echo "fe80::1%lo0 $NAME" >> $HOSTS
	echo "# Virtual host end $NAME" >> $HOSTS
	echo "" >> $HOSTS

	#restart apache
	apachectl restart

	echo "Configuration complete, test site link: http://localhost:$PORT"
}

##
# List all virtual hosts created by this tool
function listHosts {
	declare -a ARRAY
	let count=0

	while read LINE           
	do           
		if [[ $LINE == *Virtual\ host\ start* ]]
		then 
			ARRAY[$count]=$LINE
			((count++))
		fi
	done < $HOSTS
	echo "Available hosts:"
	echo ${ARRAY[@]}
}

##
# Remove host details from specified file
# Host host is defined between 'start' and 'end' marker strings
# @param file to modify
function removeHost {
	declare -a ARRAY
	let count=0
	local CAPTURE=1
	local FILE=$1
	echo "Remove host by port: $PORT from $FILE"

	# backup file
	echo "cp $FILE $FILE.backup"
	cp $FILE $FILE.backup

	while read LINE           
	do           
		if [[ $LINE == *Virtual\ host\ start* ]]
		then
			echo "here ${LINE:(-4)}"
			if [[ ${LINE:(-4)} == $PORT ]]
			then
				CAPTURE=0
			fi
		fi

		if [[ $LINE == *Virtual\ host\ end* ]]
		then
			if [ $CAPTURE -eq 0 ]; then
				CAPTURE=2
			fi
		fi

		if [ $CAPTURE -eq 1 ]; then
			ARRAY[$count]=$LINE
			((count++))
		fi

		if [ $CAPTURE -eq 2 ]; then
			CAPTURE=1
		fi
	done < $FILE
	
	# empty $FILE
	> $FILE	
	for (( i=0;i<$count;i++)); do
    	echo "${ARRAY[${i}]}" >> $FILE
	done 
}

#if no args passed, whinge and exit
if [ $# == 0 ]; then
	echo "This script will update your apache configuration to allow websites to be addressed by port number."

	echo -e "site nickname, i.e. mysite: "
	read NAME
	echo -e "port number: "
	read PORT
	echo -e "path to project, i.e. /Users/<user>/path/to/site: "
	read DIR
	ARGS_OK=1
fi

# if there are cmd line args, parse them
if [ $ARGS_OK == 0 ]; then
	#parse arguments
	while getopts "lhp:d:n:r:" opt; do
	  case $opt in
		r)
		  #remove host by port number
		  PORT=$OPTARG
		  if [ -z $PORT ]; then
			  echo "No port number given!"
			  usage
			  exit 1
		  fi
		  removeHost $HOSTS
		  removeHost $VHOSTS
		  apachectl restart
		  exit
		  ;;
		p)
		  PORT=$OPTARG
		  ;;
		n)
		  NAME=$OPTARG
		  ;;
		d)
		  DIR=$OPTARG
		  ;;
		\?)
		  echo "Invalid option: -$OPTARG" >&2
		  usage
		  exit 1
		  ;;
		l)
			listHosts
			exit 0
			;;
		h)
			usage
			exit 1
			;;
		:)
		  echo "Option -$OPTARG requires an argument." >&2
		  exit 1
		  ;;
	  esac
	done
fi

addHost
