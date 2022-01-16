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
CSV_FILE="TestPlanets.csv"
SENDGRID_API_KEY="SG.placeholder"
FROM_EMAIL="Your email here"
FROM_NAME="Your name here"
# This should be a long hex string
SG_TEMPLATE="d-placeholder"
# You can make one at https://mc.sendgrid.com/dynamic-templates

### Don't edit these ⟀
# Standardize CSV from Bridge
FIRST_LINE=`head -n 1 $CSV_FILE`
TITLES="Number,Planet,Invite URL,Point,Ticket,Email,Timestamp"
# Check if title row has all columns & replace if not
if [[ "$FIRST_LINE" != "$TITLES" ]]; then
sed -i "1s/.*/$TITLES/" $CSV_FILE;
fi
input=$1
LOG_FILE="Transaction.log"
TIMESTAMP=`date "+%Y.%m.%d-%H:%M:%S"`
# Snip email from input
EMAIL_EXTRACT=`echo $input|jq -r .email`
# Snip password from input
AUTH_EXTRACT=`echo $input|jq -r .auth`
# Mark CSV entry as sold
APPEND_STRING=`echo ,$EMAIL_EXTRACT,$TIMESTAMP`
# Cut out lines with blank 6th column
CSV_CONTENT=`awk -F, '!length($6)' $CSV_FILE`
# Snip the first one
UNUSED_LINE=(${CSV_CONTENT[@]})
# Snip out the @p, URL, and planet code
UNUSED_CODE=`echo $UNUSED_LINE | awk -F',' 'NR==1{print $3}'`
UNUSED_NAME=`echo $UNUSED_LINE | awk -F',' 'NR==1{print $2}'`
CODE_TEXT=`echo $UNUSED_LINE | awk -F',' 'NR==1{print $5}'`
GET_LINE=`echo $UNUSED_LINE | awk -F',' 'NR==1{print $1}'`
LINE_NUM=$((GET_LINE++))
# LINE_NUM=`grep -Fn $UNUSED_NAME, $CSV_FILE | grep -Eo '[0-9]{1,4}'`
# JSON payloads for SendGrid
# Use the dynamic_template_data vars in your template
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

# Debug output
                        echo $REQUEST_DATA
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
# Send email
			curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
				-H "Authorization: Bearer $SENDGRID_API_KEY" \
				-H "Content-Type: application/json" \
				-d "$REQUEST_DATA" >> $LOG_FILE
			echo  -e "\n$TIMESTAMP // Email sent to $EMAIL_EXTRACT" | tee -a "$LOG_FILE"
# Append sale to CSV line and strip double-commas
			sed -i ''${GET_LINE}'s/$/'${APPEND_STRING}'/' $CSV_FILE
                        sed -i "s/,,/,/g" $CSV_FILE
			echo "$TIMESTAMP // Transaction completed: $UNUSED_LINE,$EMAIL_EXTRACT,$TIMESTAMP" | tee -a "$LOG_FILE"

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
