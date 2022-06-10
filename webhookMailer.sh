#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>Transaction.log 2>&1
########################################################
#                                                      #
#    L2 planet sale webhook script v3                  #
#            ~sitful-hatred                            #
#                                                      #
########################################################
#                                                      #
# About:                                               #
# BtcPay submits transaction to webhook.               #
# Webhook passes to shell script, which validates      #
#+ the transaction ID & retrieves email.               #
# The email is then passed to the rest of the script,  #
#+ where a new planet code extracted, marked as used,  #
#+ and emailed to the address.                         #
# See Readme for instructions & troubleshooting        #
#                                                      #
# V2 update: imports csv to sqlite db and manages      #
#+ entries there                                       #
#                                                      #
# V3 update: switches to BTCPay Greenfield API         #
#+ instead of BtcTransmuter plugin for increased       #
#+ reliability, plus some code cleanup.                #
#                                                      #
# Note: Do not make your webhook port face the         #
# internet.                                            #
#                                                      #
########################################################
#
### Edit these ⟀
source settings.data
###
input=$1
DIR=`cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null;`
DB="${DIR}/db.sq3"
SALE_EMAIL="${DIR}/email.data"
WARN_EMAIL="${DIR}/warn.data"
TIMESTAMP=`date "+%Y.%m.%d-%H.%M.%S"`
STATUS=`echo $input|jq -r .event.name`
INVOICE=`echo $input|jq -r .data.id`
EMAIL_EXTRACT=`curl -X GET ${BTCPAY_API_URL}/invoices/${INVOICE} \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic ${BTCPAY_API_KEY}" \
    | jq -r .data.buyer.email | head -n 1`
# Store Sqlite operation vars
DB_SELECT="sqlite3 $DB 'SELECT"
DB_UPDATE="sqlite3 $DB 'UPDATE"
IMPORT_CHECK=`grep -q IMPORTED_FILE "${CSV_FILE}" ; echo $?`
FIND_UNUSED="FROM planets WHERE Email is NULL LIMIT 1;'"
APPEND_UNUSED="WHERE Email is NULL LIMIT 1;'"
LINE_NUM=`eval "$DB_SELECT rowid $FIND_UNUSED"`
UNUSED_CODE=`eval "$DB_SELECT \"Invite URL\" $FIND_UNUSED"`
UNUSED_NAME=`eval "$DB_SELECT Planet $FIND_UNUSED"`
CODE_TEXT=`eval "$DB_SELECT Ticket $FIND_UNUSED"`
DB_COUNT=`eval "$DB_SELECT COUNT(*) FROM planets;'"`
DEDUPE="'DELETE FROM planets WHERE rowid NOT IN (SELECT MIN(rowid) FROM planets GROUP BY Planet);'"


# If Greenfield API reports sold planet, begin main loop
if [[ "${STATUS}" == "invoice_confirmed" ]]
then

        # Check if there is already a DB, and import CSV if not
        DB_ABSENT=`test -f $DB; echo $?`
        if [ $DB_ABSENT == 1 ]; then
                # Standardize CSV from Bridge
                cp $CSV_FILE import.csv
                FIRST_LINE=`head -n 1 import.csv`
                TITLES="Number,Planet,Invite URL,Point,Ticket,Email,Timestamp"
                # Check if title row has all columns & replace if not
                        if [[ "$FIRST_LINE" != "$TITLES" ]]; then
                        sed -i "1s/.*/$TITLES/" import.csv;
                        fi
                sqlite3 $DB '.mode csv' '.import import.csv planets'
                rm -f import.csv
                echo "IMPORTED_FILE"
                mv $CSV_FILE IMPORTED_${CSV_FILE}
                echo "$TIMESTAMP // Database created"
        fi

        # Import CSV into DB, format & deduplicate
        if [ $IMPORT_CHECK -eq "1" ]; then
                # Import CSV to sqlite DB
                # --import was added in 3.32
                tail -n +2 "$CSV_FILE" > import.csv
                sqlite3 $DB '.mode csv' '.import import.csv planets'
                rm import.csv
                # Remove duplicate planet rows
                sqlite3 $DB $DEDUPE
                sqlite3 $DB 'VACUUM;'
                # Change numbers to match rowid
                eval "$DB_UPDATE planet SET Number = rowid;'"
                # Mark CSV as imported
                echo "IMPORTED_FILE" | tee -a $CSV_FILE
                mv $CSV_FILE IMPORTED_${CSV_FILE}
                echo "$TIMESTAMP // CSV imported"
        fi

        

        # Exclusive lock on executing script to avoid double-spends
        (
        flock -x -w 10 200 || exit 1
        # Load email request data
        source ${SALE_EMAIL}
        # Send email
        curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
                -H "Authorization: Bearer $SENDGRID_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$REQUEST_DATA"
        echo  -e "\n$TIMESTAMP // Email sent to $EMAIL_EXTRACT"

        # Mark planet row as sold
        eval "$DB_UPDATE planets SET Email = \"$EMAIL_EXTRACT\", \
        Timestamp = \"$TIMESTAMP\" $APPEND_UNUSED"
        REMAINING=$((LINE_NUM-DB_COUNT))
        echo "$TIMESTAMP // $UNUSED_NAME marked as sold to $EMAIL_EXTRACT"
        echo "$REMAINING of $DB_COUNT planet codes remaining"

        ) 200>lock.file

fi

# Test whether any more planets are available
if [ $LINE_NUM -eq $DB_COUNT ]; then
# Load warning email data
source ${WARN_EMAIL}
# Email me if no more planets
curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$WARN_DATA"
echo "WARNING: No more planets!"
fi
