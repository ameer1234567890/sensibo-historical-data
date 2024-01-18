#!/bin/bash

# shellcheck disable=SC2116

cd "$(dirname "$0")" || exit 1

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

progress() {
  shopt -s checkwinsize; (:);
  local num_completed=$1
  local num_total=$2
  local full=$((COLUMNS - 10))
  local percent_completed=$((num_completed * full / num_total))
  local perc_comp=$((num_completed * 100 / num_total))
  local percent_remaining=$((full - percent_completed + 1))
  if [ $percent_remaining -gt $full ]; then
    percent_remaining=$full
  fi
  printf "["
  printf %${percent_completed}s | tr " " "="
  printf %${percent_remaining}s | tr -s " " ">"
  printf %${percent_remaining}s
  printf "$perc_comp%% ]\r"
  if [ $percent_remaining -lt 2 ]; then
    printf "["
    printf %${full}s | tr " " "="
    printf "=======]\r"
  fi
}

# check if the date utility has the required capabilities
if [ "$(date -d "2019-09-09T15:54:31.996176128Z" "+%d/%m/%Y, %H:%M:%S" 2>/dev/null)" = "" ]; then
  log "Date utility does not have the required capabilities. Consider installing \"coreutils-date\"!"
  exit 1
fi

if [ ! -d './tmp' ]; then
  mkdir ./tmp
fi

PID_FILE=tmp/sensibo.pid
if [ -f $PID_FILE ]; then
  pid=$(cat $PID_FILE)
  ps | awk '{print $1}' | grep "$pid"
  status="$?"
  if [ "$status" != 0 ]; then
    rm $PID_FILE
  else
    log "Another instance is already running! Exiting..."
    exit 1
  fi
fi
trap 'rm -f -- "$PID_FILE"' exit
echo $$ > "$PID_FILE"

log "Requesting Sensibo API data..."
http_status_code=$(curl -o tmp/api.json -w '%{http_code}\n' "https://home.sensibo.com/api/v2/pods/$SENSIBO_DEVICE_ID/historicalMeasurements?apiKey=$SENSIBO_API_KEY")
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
echo '{"cols":[{"label":"Time","type":"string"},{"label":"Temperature (°C)","type":"number"},{"label":"Humidity (%)","type":"number"}],"rows": [' > tmp/data-temp.json

paste -d " " tmp/data-temperature.json tmp/data-humidity.json > tmp/data-combined.json

c=0;
while read -r line; do
  c=$(("$c" + 1))
  if [ "$c" != "$lines" ]; then
    line_end=","
  else
    line_end=""
  fi
  progress "$c" "$lines"
  # shellcheck disable=SC2206
  arr=($line)
  closing_curly_bracket="}"
  comma=","
  double_quote="\""
  temperature=$(echo "${arr[3]%"$comma"}")
  temperature=$(echo "${temperature%"$closing_curly_bracket"}")
  time=$(echo "${arr[1]%"$comma"}")
  time=$(echo "${time#"$double_quote"}")
  time=$(echo "${time%"$double_quote"}")
  time_local=$(date -d "$time" "+%d/%m/%Y, %H:%M:%S")
  humidity=$(echo "${arr[7]%"$comma"}")
  humidity=$(echo "${humidity%"$closing_curly_bracket"}")
  { printf '{"c":[{"v":"'; printf %s "$time_local"; printf '"},{"v":'; printf %s "$temperature"; printf '},{"v":'; printf %s "$humidity"; printf '}]}%s\n' "$line_end"; } >> tmp/data-temp.json
done <tmp/data-combined.json

echo ']}' >> tmp/data-temp.json
echo "" # end of progress

cp tmp/data-temp.json www/data.json
rm tmp/data-temp.json
rm tmp/data-temperature.json
rm tmp/data-humidity.json

log "Done!"
