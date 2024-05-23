#!/bin/bash
set -e

ipv4Regex="((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
ipv6Regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

ipv6="true"
# proxy="true"
# ask for existing proxy, don't override it <.<

# DSM Config
username="$1"
password="$2"
hostname="$3"
ipAddr="$4"

# Fetch and filter IPv6, if Synology won't provide it
if [[ $ipv6 == "true" ]]; then
  ip6fetch=$(ip -6 addr show eth0 | grep -oP "$ipv6Regex" || true)
  ip6Addr=$(if [ -z "$ip6fetch" ]; then echo ""; else echo "${ip6fetch:0:$((${#ip6fetch})) - 7}"; fi) # in case of NULL, echo NULL
  recType6="AAAA"

  if [[ -z "$ip6Addr" ]]; then
    ipv6="false" # if only ipv4 is available
  fi
  if [[ $ipAddr =~ $ipv4Regex ]]; then
    recordType="A"
  else
    recordType="AAAA"
    ipv6="false" # because Synology had provided the IPv6
  fi
else
  recordType="A"
fi

# Cloudflare API-Calls for listing entries
listDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=A&name=${hostname}"
listDnsv6Api="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=AAAA&name=${hostname}" # if only IPv4 is provided

res=$(curl -s -X GET "$listDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $ipv6 == "true" ]]; then
  resv6=$(curl -s -X GET "$listDnsv6Api" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
fi

if [[ $resSuccess != "true" ]]; then
  echo "badauth"
  exit 1
fi

# Update all IPv4 records
for record in $(echo "$res" | jq -c '.result[]'); do
  recordId=$(echo "$record" | jq -r ".id")
  recordIp=$(echo "$record" | jq -r ".content")
  recordProx=$(echo "$record" | jq -r ".proxied")

  if [[ $recordIp != "$ipAddr" ]]; then
    res=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordId}" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$recordProx}")
    resSuccess=$(echo "$res" | jq -r ".success")
    if [[ $resSuccess != "true" ]]; then
      echo "badauth"
      exit 1
    fi
  fi
done

# Update all IPv6 records if available
if [[ $ipv6 == "true" ]]; then
  for record in $(echo "$resv6" | jq -c '.result[]'); do
    recordIdv6=$(echo "$record" | jq -r ".id")
    recordIpv6=$(echo "$record" | jq -r ".content")
    recordProxv6=$(echo "$record" | jq -r ".proxied")

    if [[ $recordIpv6 != "$ip6Addr" ]]; then
      res6=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordIdv6}" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"AAAA\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$recordProxv6}")
      res6Success=$(echo "$res6" | jq -r ".success")
      if [[ $res6Success != "true" ]]; then
        echo "badauth"
        exit 1
      fi
    fi
  done
fi

echo "good"
