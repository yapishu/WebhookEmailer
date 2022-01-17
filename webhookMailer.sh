#!/bin/bash
########################################################
#                                                      #
#    L2 planet sale webhook script v2                  #
#            ~sitful-hatred                            #
#                                                      #
########################################################
#                                                      #
# About:                                               #
# Btctransmuter submits PUT request to webhook.        #
# The PUT contains json with email & auth key.         #
# Webhook passes to shell script, which validates      #
#+ the email address and password.                     #
# The email is then passed to the rest of the script,  #
#+ where a new planet code extracted, marked as used,  #
#+ and emailed to the address.                         #
# See Readme for instructions & troubleshooting        #
#                                                      #
# V2 update: imports csv to sqlite db and manages      #
#+ entries there                                       #
#
########################################################
#
### Edit these ⟀
# Code for webhook to authenticate (20+ chars recommended)
AUTH_CODE="PlaceholderPassword"
# Path to CSV
CSV_FILE="planets.csv"
SENDGRID_API_KEY="SG.placeholder"
FROM_EMAIL="Your email here"
FROM_NAME="Your name here"
# This should be a long hex string
SG_TEMPLATE="d-placeholder"
# You can make one at https://mc.sendgrid.com/dynamic-templates
# Be sure to have ${UNUSED_NAME}, ${UNUSED_CODE} 
# and ${CODE_TEXT} vars in your template

### Don't edit these ⟀
input=$1
LOG_FILE="Transaction.log"
TIMESTAMP=`date "+%Y.%m.%d-%H.%M.%S"`

# Snip email from input
EMAIL_EXTRACT=`echo $input|jq -r .email`
# Snip password from input
AUTH_EXTRACT=`echo $input|jq -r .auth`

# Check if there is already a DB, and import CSV if not
DB=db.sq3
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
    echo "IMPORTED_FILE" | tee -a $CSV_FILE
    mv $CSV_FILE IMPORTED_${CSV_FILE}
fi

DB_SELECT="sqlite3 $DB 'SELECT"
DB_UPDATE="sqlite3 $DB 'UPDATE"
IMPORT_CHECK=`grep -q IMPORTED_FILE "${CSV_FILE}" ; echo $?`

if [ $IMPORT_CHECK -eq "1" ]; then
    # Import CSV to sqlite DB
    # --import was added in 3.32
    tail -n +2 "$CSV_FILE" > import.csv
    sqlite3 $DB '.mode csv' '.import import.csv planets'
    rm import.csv
    # Change numbers to match rowid
    eval "$DB_UPDATE planet SET Number = rowid;'"
    # Mark CSV as imported
    echo "IMPORTED_FILE" | tee -a $CSV_FILE
    mv $CSV_FILE IMPORTED_${CSV_FILE}
fi

# Sqlite operation vars
FIND_UNUSED="FROM planets WHERE Email is NULL LIMIT 1;'"
APPEND_UNUSED="WHERE Email is NULL LIMIT 1;'"
LINE_NUM=`eval "$DB_SELECT rowid $FIND_UNUSED"`
UNUSED_CODE=`eval "$DB_SELECT \"Invite URL\" $FIND_UNUSED"`
UNUSED_NAME=`eval "$DB_SELECT Planet $FIND_UNUSED"`
CODE_TEXT=`eval "$DB_SELECT Ticket $FIND_UNUSED"`
DB_COUNT=`eval "$DB_SELECT COUNT(*) FROM planets;'"`

# Email data
REQUEST_DATA='{ "from": {
                "email": "'${FROM_EMAIL}'",
                "name": "'${FROM_NAME}'"
        },
        "personalizations": [{
                "to": [{
                 "email": "'${EMAIL_EXTRACT}'"
                     }],
                                 "bcc": [{
                                 "email": "'${FROM_EMAIL}'"
                                 }],
        "dynamic_template_data": {
                "planet-code": "'${UNUSED_CODE}'",
                "planet-name": "'${UNUSED_NAME}'",
                "code-text":"'${CODE_TEXT}'"
        }
                        }],
        "template_id": "'${SG_TEMPLATE}'"
}';
BOUNCE_DATA='{ "from": {
                "email": "'${FROM_EMAIL}'",
                "name": "'${FROM_NAME}'"
        },
        "personalizations": [{
                "to": [{
                 "email": "'${FROM_EMAIL}'"
                     }],
                        }],
        "subject": "Email validation failure",
                "content":
                        [{"type": "text/plain", "value": "Email address validation failed, check logs"}]
}';
WARN_DATA='{ "from": {
                "email": "'${FROM_EMAIL}'",
                "name": "'${FROM_NAME}'"
        },
        "personalizations": [{
                "to": [{
                 "email": "'${FROM_EMAIL}'"
                     }],
                        }],
        "subject": "WARNING: Final planet sold",
                "content":
                        [{"type": "text/plain", "value": "No more planets available for sale, restock"}]
}';

# Debug output
echo $input
echo "$CODE_TEXT"

# Function to validate email address
function isEmailValid() {
    regex="^([A-Za-z]+[A-Za-z0-9]*((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*){1,})@(([A-Za-z]+[A-Za-z0-9]*)+((\.|\-|\_)?([A-Za-z]+[A-Za-z0-9]*)+){1,})+\.([A-Za-z]{2,})+"
    [[ "${1}" =~ $regex  ]]
}

# Exclusive lock on executing script to avoid double-spends
(
flock -x -w 10 200 || exit 1

# Check whether auth code matches
if [ "$AUTH_EXTRACT" = "$AUTH_CODE" ];then
       echo "$TIMESTAMP // Authentication succeeded: $AUTH_EXTRACT" | tee -a "$LOG_FILE"

# Validate email
        if isEmailValid "$EMAIL_EXTRACT" ;then

# Email is valid send email
                        curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
                                -H "Authorization: Bearer $SENDGRID_API_KEY" \
                                -H "Content-Type: application/json" \
                                -d "$REQUEST_DATA" >> $LOG_FILE
                        echo  -e "\n$TIMESTAMP // Email sent to $EMAIL_EXTRACT" | tee -a "$LOG_FILE"

# Mark planet row as sold
            eval "$DB_UPDATE planets SET Email = \"$EMAIL_EXTRACT\", \
            Timestamp = \"$TIMESTAMP\" $APPEND_UNUSED"

# Invalid email: mark to log
        else echo "$TIMESTAMP // $EMAIL_EXTRACT did not pass validation"  | tee -a "$LOG_FILE"

# Email me if the recipient address is bad
                        curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
                                -H "Authorization: Bearer $SENDGRID_API_KEY" \
                                -H "Content-Type: application/json" \
                                -d "$BOUNCE_DATA" >> $LOG_FILE

        fi

    else echo "$TIMESTAMP // Failed validation: $AUTH_EXTRACT does not match $AUTH_CODE" | tee -a "$LOG_FILE"
fi
) 200>lock.file

# Test whether any more planets are available
if [ $LINE_NUM -eq $DB_COUNT ]; then
# Email me if no more planets
curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$WARN_DATA" >> $LOG_FILE
fi
