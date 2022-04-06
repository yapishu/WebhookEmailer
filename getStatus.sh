#!/bin/bash
# Easily query database status
# $> ./getStatus.sh
ROW_COUNT=`eval "sqlite3 /etc/webhook/data/db.sq3 'SELECT COUNT(*) FROM planets;'"`
AVAIL_ROW=`eval "sqlite3 /etc/webhook/data/db.sq3 'SELECT Number FROM planets WHERE Email is NULL LIMIT 1;'"`
SOLD_COUNT=`echo $(($AVAIL_ROW))`
REMAINING=`echo $(($ROW_COUNT-$SOLD_COUNT))`

echo "#######################"
echo "NetSub planet shooter stats"
echo "#######################"
echo
echo "Number of planets in DB:"
echo "-------------"
echo $ROW_COUNT
echo
echo "Number of planets sold:"
echo "-------------"
echo $SOLD_COUNT
echo
echo "Most recently sold planet:"
echo "-------------"
eval "sqlite3 /etc/webhook/data/db.sq3 'SELECT Planet FROM planets WHERE rowid = $SOLD_COUNT;'"
eval "sqlite3 /etc/webhook/data/db.sq3 'SELECT Timestamp FROM planets WHERE rowid = $SOLD_COUNT;'"
eval "sqlite3 /etc/webhook/data/db.sq3 'SELECT Email FROM planets WHERE rowid = $SOLD_COUNT;'"
echo
echo "Number of remaining available planets:"
echo "-------------"
echo $REMAINING
