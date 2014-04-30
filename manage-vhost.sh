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
# usage:
# TS=$(timestamp)
# echo $TS
function timestamp() {
	local __result=`date +"%Y%m%d-%H%M%S"`
	echo "$__result"
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
	echo "-R : restore config files to defaults"
	echo "NB: arguments can be given in any order."
	echo ""
	echo "Run with no arguments for interactive mode"
	echo "example: manage-vhost -n mysite -p 9999 -d ~/path/to/site/"
	echo "On completion, the site will be available at localhost:9999"
}

##
# Clean up vhosts file, remove dummy entries
function cleanupVhosts() {
	cp $VHOSTS $VHOSTS.backup

	sed -i '' "/NameVirtualHost \*:80/d" $VHOSTS
	sed -i '' "/\<VirtualHost \*:80\>/,/\<\/VirtualHost\>/d" $VHOSTS
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
		sed -i '' "s/#Include \/private\/etc\/apache2\/extra\/httpd-vhosts.conf/Include \/private\/etc\/apache2\/extra\/httpd-vhosts.conf/" /etc/apache2/httpd.conf
	fi

	#Create httpd-vhosts.conf(if necessary)
	if [ ! -f $VHOSTS ]; then
		echo "Create $VHOSTS"
		touch $VHOSTS
	fi

	# backup original vhost file, remove dummy entries
	cleanupVhosts

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
	let i=0

	while read LINE           
	do           
		if [[ $LINE == *Virtual\ host\ start* ]]
		then 
			ARRAY[$count]=$LINE
			((count++))
		fi
	done < $HOSTS
	echo "Available hosts:"
	for (( i=0;i<$count;i++)); do
    	echo "${ARRAY[${i}]}"
	done 
}

##
# Remove host details from specified file
# Host host is defined between 'start' and 'end' marker strings
# @param file to modify
function removeHost {
	declare -a ARRAY
	let count=0
	let i=0
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

function restore() {
	echo "Restore $VHOSTS and $HOSTS to defaults."
	if [ ! -f $VHOSTS.modified ]; then
		cp $VHOSTS $VHOSTS.modified
	fi

	if [ ! -f $HOSTS.modified ]; then
		cp $HOSTS $HOSTS.modified
	fi
	cp /etc/apache2/httpd.conf.abacus /etc/apache2/httpd.conf

	echo '#' > $VHOSTS
	echo '# Virtual Hosts' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '# If you want to maintain multiple domains/hostnames on your' >> $VHOSTS
	echo '# machine you can setup VirtualHost containers for them. Most configurations' >> $VHOSTS
	echo "# use only name-based virtual hosts so the server doesn't need to worry about" >> $VHOSTS
	echo '# IP addresses. This is indicated by the asterisks in the directives below.' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '# Please see the documentation at ' >> $VHOSTS
	echo '# <URL:http://httpd.apache.org/docs/2.2/vhosts/>' >> $VHOSTS
	echo '# for further details before you try to setup virtual hosts.' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '# You may use the command line option '-S' to verify your virtual host' >> $VHOSTS
	echo '# configuration.' >> $VHOSTS
	echo '' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '# Use name-based virtual hosting.' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo 'NameVirtualHost *:80' >> $VHOSTS
	echo '' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '# VirtualHost example:' >> $VHOSTS
	echo '# Almost any Apache directive may go into a VirtualHost container.' >> $VHOSTS
	echo '# The first VirtualHost section is used for all requests that do not' >> $VHOSTS
	echo '# match a ServerName or ServerAlias in any <VirtualHost> block.' >> $VHOSTS
	echo '#' >> $VHOSTS
	echo '<VirtualHost *:80>' >> $VHOSTS
	echo '    ServerAdmin webmaster@dummy-host.example.com' >> $VHOSTS
	echo '    DocumentRoot "/usr/docs/dummy-host.example.com"' >> $VHOSTS
	echo '    ServerName dummy-host.example.com' >> $VHOSTS
	echo '    ServerAlias www.dummy-host.example.com' >> $VHOSTS
	echo '    ErrorLog "/private/var/log/apache2/dummy-host.example.com-error_log"' >> $VHOSTS
	echo '    CustomLog "/private/var/log/apache2/dummy-host.example.com-access_log" common' >> $VHOSTS
	echo '</VirtualHost>' >> $VHOSTS
	echo '' >> $VHOSTS
	echo '<VirtualHost *:80>' >> $VHOSTS
	echo '    ServerAdmin webmaster@dummy-host2.example.com' >> $VHOSTS
	echo '    DocumentRoot "/usr/docs/dummy-host2.example.com"' >> $VHOSTS
	echo '    ServerName dummy-host2.example.com' >> $VHOSTS
	echo '    ErrorLog "/private/var/log/apache2/dummy-host2.example.com-error_log"' >> $VHOSTS
	echo '    CustomLog "/private/var/log/apache2/dummy-host2.example.com-access_log" common' >> $VHOSTS
	echo '</VirtualHost>' >> $VHOSTS
	echo '' >> $VHOSTS

	echo "##" > $HOSTS
	echo "# Host Database" >> $HOSTS
	echo "#" >> $HOSTS
	echo "# localhost is used to configure the loopback interface" >> $HOSTS
	echo "# when the system is booting.  Do not change this entry." >> $HOSTS
	echo "##" >> $HOSTS
	echo "127.0.0.1	localhost" >> $HOSTS
	echo "255.255.255.255	broadcasthost" >> $HOSTS
	echo "::1             localhost" >> $HOSTS
	echo "fe80::1%lo0	localhost" >> $HOSTS
	echo "" >> $HOSTS

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
	while getopts "lhRp:d:n:r:" opt; do
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
		R)
			restore
		  	apachectl restart
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
