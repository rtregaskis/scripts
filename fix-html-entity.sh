#!/bin/bash

if [ $# == 0 ]; then
	echo "No args passed!";
	echo "script requires a path to files to operate upon"
	exit -1
fi

# read in file, convertdefined set of characters to corresponding html entity tags
#NB: uses perl to do replacement as Mac OSX sed is broken...
FILES=("$@")

for file in $FILES; do
	perl -pi -e 's/®/&reg;/g' $file
	perl -pi -e 's/£/&pound;/g' $file
done
