# Layer 2 Webhook Emailer

## Introduction

This is my attempt at stringing together [BTCPay Server](https://github.com/btcpayserver/btcpayserver), [SendGrid](https://sendgrid.com/), and rudimentary data management via CSV parsing. This will allow you to collect payment from BTCPay, and automatically trigger an email with a planet code to the email submitted by the customer. 

You need to have a SendGrid account and API key -- you get 100 emails/day with a free account.

## Configuration

First install the prereqs:

```
$> sudo apt install jq curl webhook
```

Open `webhookMailer.sh` and edit the first block of variables with your information. A CSV with test data is included -- this script is written to parse CSVs by identifying the first available row with two columns of data (name and code), extract the data, and append sales info. The next time it is run, it will choose the next row down. There is no accommodation for running out of rows, so keep an eye on it (BTCPay allows you to set inventory numbers -- I recommend aligning
this with the number of entries in your CSV). 

You can test it by running the hook:

```
$> webhook -hooks emailer.json -verbose
```

Then curling a fake request and making sure it executes properly:

```
$> curl -H Content-Type: application/json -d {"auth":"long_password","email":"your.email@gmail.com"} -X PUT http://localhost:9000/hooks/emailer
```

### systemd

Included is a systemd module. Edit the username and path, copy it and enable it:

```
$> sudo cp emailer.service /etc/systemd/system/emailer.service
$> sudo systemctl enable emailer
$> sudo systemctl start emailer
```

This will allow the webhook to automatically run as a service.

## Connecting to BtcTransmuter

TODO

## Troubleshooting

There is a primitive logging system implemented -- look at `Transactions.log` and see if it's catching on anything. 
