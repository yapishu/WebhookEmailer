# Layer 2 Webhook Emailer

## Overview

See a live version of this implementation at the [subject.network](https://subject.network/buy) planet store.

This is my project to connect [BTCPay Server](https://github.com/btcpayserver/btcpayserver), [SendGrid](https://sendgrid.com/), and simple database management. The first two versions of this were a shell script and webhook configuration, this is a Python- and Docker-ized version with additional functionality, including automatic listings generated for BTCPay (but you'll still need to manually paste them in).

This script will allow you to collect payment from BTCPay, and automatically trigger an email with a planet code to the email submitted by the customer after payment is confirmed. It will import an L2 planet code CSV from [Bridge](https://bridge.urbit.org) and deduplicate any existing entries. This configuration assumes you are running the container on the host device running the Docker container, but you don't have to.

You need to have a SendGrid account with a validated email, API key, and [dynamic template](https://mc.sendgrid.com/dynamic-templates) -- you get 100 emails/day with a free account. You will also need to provide it with a CSV of planets & codes, but a test set is included. Delete `db.sq3` to clear the state.

## Configuration

You need docker & compose installed, and a BTCPayServer store installed and configured.

Copy the variables from the compose file into a `.env` file and assign them:

- `API_KEY` -- the BTCPay API key
- `SG_API` -- SendGrid API key
- `TEMPLATE_ID` -- SendGrid dynamic template ID
- `URL` -- URL for BTCPay that is accessible from inside container (`http://172.20.0.1:80` or whatever the docker gateway IP is should work)
- `S3_URL` -- S3 API endpoint
- `S3_ACCESS` -- S3 access key
- `S3_SECRET` -- S3 secret key
- `S3_BUCKET` -- S3 bucket name
- `GIFT_AUTH` -- Password used to send gift planets

Note that I've had [issues](https://github.com/benbjohnson/litestream/issues/435) with Litestream behaving badly on S3 providers other than [DigitalOcean](https://m.do.co/c/4da920651e1a) (referral).

The container will use the `./data` directory to store the DB. Copy the template DB into this directory and name it `db.sq3`.

After your variables are set, simply run `docker-compose up -d`.

When app runs, it will look for a CSV named `./data/planets.csv` and import it into a DB, then mark it as imported. It will not re-import a CSV if it has 'IMPORTED_DATA' appended to it. 

You can easily query the sales stats of the DB by GETing the `/` route (root path).


## Connecting to BtcPay

At the bottom of your store's page, expand the 'Notification URL Callbacks' modal and enter `http://sales-hook:5000` or `http://172.20.0.1:5000` as the URL (or whatever the address is as reachable from BTCPay).

## Generating planet listings

This version (v3) includes functions to automatically generate BTCPay listings in text format and upload SVGs of the sigils to your S3 bucket.


This function is not exposed so you'll need to get a REPL shell and run the following commands:

```bash
docker exec -it sales-hook /bin/bash
cd app
python
import app
app.inventory_gen(50)
```

This will generate 50 individual planet listings and take the planets out of the random pool (which is the default). The listings will be output to `./data/inventory/inv.txt`.

You can paste the content of the text into the store's listings:

![](https://i.imgur.com/TzlkgKX.png)

### Important

This will BCC my email on a sale! It is hardcoded at the moment, edit the function on line 266 in `app.py` before you run this.
