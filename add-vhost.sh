#!/bin/bash

HERE=$(pwd)
PORT=""
DIR=""
NAME=""

echo "Abacus Virtual Host Setup."
echo ""

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

function usage {
	echo "usage: add-vhost -n NAME -p PORT -d DIRECTORY"
	echo "-h : this usage message"
	echo "-n : name of site, i.e. product name"
	echo "-p : port number to access site by, i.e. "
	echo "     project code or memorable port number if code is 0000"
	echo "-d : top-level directory of project"
	echo "NB: arguments can be given in any order."
	echo ""
	echo "example: add-vhost -n nuvotide -p 4361 -d ~/work/4361-USModelAdaptation/"
	echo "On completion, the site will be available at localhost:4361"
}

#if no args passed, whinge and exit
if [ $# == 0 ]; then
	echo "No arguments passed!"
	usage
	exit
fi

#parse arguments
while getopts "hp:d:n:d" opt; do
  case $opt in
    p)
      #echo "-p was triggered, Parameter: $OPTARG" >&2
	  PORT=$OPTARG
      ;;
    n)
      #echo "-n was triggered, Parameter: $OPTARG" >&2
	  NAME=$OPTARG
      ;;
    d)
      #echo "-d was triggered, Parameter: $OPTARG" >&2
	  DIR=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
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
VHOSTS="/etc/apache2/extra/httpd-vhosts.conf"
if [ ! -f $VHOSTS ]; then
	echo "Create $VHOSTS"
	touch $VHOSTS
fi

echo "Append site details to $VHOSTS"
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

# append details to /etc/hosts
HOSTS="/etc/hosts"

echo "Append site details to $HOSTS"
echo "# Abacus virtual host start" >> $HOSTS
echo "127.0.0.1 $NAME" >> $HOSTS
echo "fe80::1%lo0 $NAME" >> $HOSTS
echo "# Abacus virtual host end" >> $HOSTS

#restart apache
apachectl restart

echo "Configuration complete, test site link: http://localhost:$PORT"
