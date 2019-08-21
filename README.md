[![Build Status](https://travis-ci.org/ameer1234567890/sensibo-historical-data.svg?branch=master)](https://travis-ci.org/ameer1234567890/sensibo-historical-data)

#### Works with
* bash
* Git Bash on Windows.

#### Requirements
* cURL
* If you are on openWRT, you need to install `coreutils-date` package.
* Some patience.

#### Setup Instructions
* Clone this repository.
* cd into repo directory.
* Run `./sensibo.sh` and wait for it to complete.
* Serve `www` directory via a web server.
* You can set the script to run periodically via cron, in order to keep data updated. I suggest intervals >= 5 minutes.
