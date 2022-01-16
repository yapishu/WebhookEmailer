# Layer 2 Webhook Emailer

## Introduction

This is my project to connect [BTCPay Server](https://github.com/btcpayserver/btcpayserver), [SendGrid](https://sendgrid.com/), and simple database management. This will allow you to collect payment from BTCPay, and automatically trigger an email with a planet code to the email submitted by the customer after payment is confirmed. This repo contains the webhook configuration, and the shell script that it triggers. This configuration assumes you are running the webhook on the host device running the Docker container, but you don't have to.

You need to have a SendGrid account with a validated email, API key, and [dynamic template](https://mc.sendgrid.com/dynamic-templates) -- you get 100 emails/day with a free account. You will also need to provide it with a CSV of planets & codes, but a test set is included.

## Configuration

First install the prereqs:

```
$> sudo apt install jq curl webhook sqlite3
```

Open `webhookMailer.sh` and edit the first block of variables with your information. A CSV with test data is included -- this script is written to import the CSV into a sqlite database, find the first available row in the DB, extract the name and code, and append sales info. The next time it is run, it will choose the next row down. If you run out of rows, it will send you an email (BTCPay allows you to set inventory numbers -- I recommend aligning this with the number of entries in your DB).

The first time your script runs, it will look for a CSV with the name you set as a variable at the top of `webhookMailer.sh` and import it into a DB, then mark it as imported. Do not rename a 'spent' CSV back to that name unless you want duplicate entries in your DB. You can easily query the sales stats of the DB by running `./getStatus.sh`. 

You can test it by running the hook; edit `emailer.json` to correct the path to the shell script before you run it.

```
$> webhook -hooks emailer.json -verbose
```

Then curling a fake request and making sure it executes properly:

```
$> curl -H Content-Type: application/json -d {"auth":"long_password","email":"your.email@gmail.com"} -X PUT http://localhost:9000/hooks/emailer
```

Note that this has basic password protection, but was designed assuming that the webhook is not exposed to the internet. If it is, you should probably not accept connections from any non-whitelisted IP addresses. `webhook` supports this [via configuration](https://github.com/adnanh/webhook/blob/master/docs/Hook-Examples.md#incoming-bitbucket-webhook):

```
"trigger-rule":
    {
      "match":
      {
        "type": "ip-whitelist",
        "ip-range": "104.192.143.0/24"
      }
    }
```

CIDR notation -- if you just want to whitelist a single address, put `/32` at the end. 

Or, you can set firewall rules on your host. 

### systemd

Included is a systemd module. **Edit the username and path** in the file, then copy it and enable it:

```
$> sudo cp emailer.service /etc/systemd/system/emailer.service
$> sudo systemctl enable emailer
$> sudo systemctl start emailer
```

This will allow the webhook to automatically run as a service.

## Connecting to BtcTransmuter

Once BTCPay and Transmuter are installed and configured and you have a store (separate instructions), go to Recipes in the Transmuter menu, and add a new Action Group. 

Set the recipe to trigger on 'paid'. On the Recipe Action screen, select 'Make web request.'

![](https://i.imgur.com/l74mWwX.png)

Enter the IP of your Docker interface (`docker0`, enter `ip a` and look through the list). For 'Method', select PUT. 

In the body, enter the JSON that will be submitted with your static passcode and the customer email variable:

```
{"auth":"yourlongpasswordhere","email":"{{TriggerData.Invoice.Buyer.email}}"}
```

(The password should match the one at the top of `webhookMailer.sh`).

You can create a store listing for an item that costs $0 to test.


## Troubleshooting

There is a primitive logging system implemented -- look at `Transactions.log` and see if it's catching on anything. 

If you need to test different layers, you can curl the webhook directly from the command line:

```
curl -H Content-Type: application/json -d {"auth":"putapasswordhere","email":"test.email@gmail.com"} -X PUT http://localhost:9000/hooks/emailer
```

Or, you can submit json parameters to the shell script itself:

```
./webhookMailer.sh "{\"auth\":\"secret_password\",\"email\":\"user.name@gmail.com\"}"
```

If something breaks, poking between these layers should help you narrow it down.
