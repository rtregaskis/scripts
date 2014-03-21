#!/bin/bash

# read in file, convertdefined set of characters to corresponding html entity tags
#NB: uses perl to do replacement as Mac OSX sed is broken...
REFS=assets/data/references/*.json

for ref in $REFS; do
	perl -pi -e 's/®/&reg;/g' $ref
	perl -pi -e 's/£/&pound;/g' $ref
done
