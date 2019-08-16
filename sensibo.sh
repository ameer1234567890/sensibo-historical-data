#!/bin/bash

# shellcheck disable=SC1091
source api.conf
# api.conf file should have the below:
if [ -z "$SENSIBO_API_KEY" ] || [ -z "$SENSIBO_DEVICE_ID" ]; then
  SENSIBO_API_KEY="SENSIBO_API_KEY" # obtain an API key from https://home.sensibo.com/me/api
  SENSIBO_DEVICE_ID="SENSIBO_DEVICE_ID" # obtain device ID from https://home.sensibo.com/api/v2/users/me/pods?apiKey={API_KEY}
fi
# end api.conf

log() {
  echo "$1"
  if [ "$(command -v logger)" ]; then
    logger -t sensibo "$1"
  fi
}

if [ ! -d './tmp' ]; then
  mkdir ./tmp
fi

PID_FILE=tmp/sensibo.pid
if [ -f $PID_FILE ]; then
  log "Another instance is already running! Exiting..."
  exit 1
fi
trap 'rm -f -- "$PID_FILE"' exit
echo $$ > "$PID_FILE"

log "Requesting Sensibo API data..."
http_status_code=$(curl -o tmp/api.json -w '%{http_code}\n' https://home.sensibo.com/api/v2/pods/$SENSIBO_DEVICE_ID/historicalMeasurements?apiKey=$SENSIBO_API_KEY)
curl_status_code="$?"
if [ "$curl_status_code" != 0 ]; then
  log "cURL request failed! cURL status code: $curl_status_code"
  exit 1
fi
if [ "$http_status_code" != 200 ]; then
  log "Invalid API response! HTTP status code: $http_status_code"
  exit 1
fi
if [ ! -f tmp/api.json ]; then
  log "Missing api.json file!"
  exit 1
fi
if ! grep -q "{\"status\": \"success\"" < tmp/api.json; then
  log "Invalid API response!"
  exit 1
fi

# shellcheck disable=SC2002
cat tmp/api.json | sed s/'{"status": "success", "result": {"temperature": \['/''/g | sed s/'\], "humidity": \[.*$'/''/g | sed s/'}, {'/'},\n{'/g > tmp/data-temperature.json

# shellcheck disable=SC2002
cat tmp/api.json | sed s/'^.*}\], "humidity": \['/''/g | sed s/']}}$'/''/g | sed s/'}, {'/'},\n{'/g > tmp/data-humidity.json

lines=$(wc -l < tmp/data-temperature.json)
# shellcheck disable=SC2009
log "Lines to process: $lines"
printf "Processing"
echo '{"cols":[{"label":"Time","type":"string"},{"label":"Temperature (°C)","type":"number"},{"label":"Humidity (%)","type":"number"}],"rows": [' > tmp/data-temp.json
# shellcheck disable=SC2004
for (( c=1; c<="$lines"; c++ )); do
  if [ "$c" != "$lines" ]; then
    line_end=","
  else
    line_end=""
  fi
  printf ".%s" "$c"
  temperature=$(sed -n "${c}p" tmp/data-temperature.json | awk '{print $2}' | cut -d ',' -f 1)
  time=$(sed -n "${c}p" tmp/data-temperature.json | awk '{print $4}' | cut -d '"' -f 2)
  time_local=$(date -d "$time" "+%d/%m/%Y, %H:%M:%S")
  humidity=$(sed -n "${c}p" tmp/data-humidity.json | awk '{print $2}' | cut -d ',' -f 1)
  { printf '{"c":[{"v":"'; printf %s "$time_local"; printf '"},{"v":'; printf %s "$temperature"; printf '},{"v":'; printf %s "$humidity"; printf '}]}%s\n' "$line_end"; } >> tmp/data-temp.json
done
echo ']}' >> tmp/data-temp.json
echo ". Done"
cp tmp/data-temp.json data.json
rm tmp/data-temp.json
rm tmp/data-temperature.json
rm tmp/data-humidity.json

log "Done!"
