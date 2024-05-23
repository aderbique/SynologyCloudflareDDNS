#!/bin/bash
set -e

ipv4Regex="((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
ipv6Regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

# DSM Config
username="$1"
password="$2"
hostname="$3"
ipAddr="$4"

# Get Zone ID from hostname
zoneApi="https://api.cloudflare.com/client/v4/zones?name=${hostname}"
zoneRes=$(curl -s -X GET "$zoneApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
zoneId=$(echo "$zoneRes" | jq -r ".result[0].id")

if [[ $zoneId == "null" ]]; then
    echo "badauth"
    exit 1
fi

# Cloudflare API-Call for listing all A and AAAA records in the zone
listARecordsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records?type=A"
listAAAARecordsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records?type=AAAA"

# Fetch A records
resA=$(curl -s -X GET "$listARecordsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resASuccess=$(echo "$resA" | jq -r ".success")

if [[ $resASuccess != "true" ]]; then
    echo "badauth"
    exit 1
fi

# Fetch AAAA records
resAAAA=$(curl -s -X GET "$listAAAARecordsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resAAAASuccess=$(echo "$resAAAA" | jq -r ".success")

if [[ $resAAAASuccess != "true" ]]; then
    echo "badauth"
    exit 1
fi

# Update all A records with the new IP address
for record in $(echo "$resA" | jq -c '.result[]'); do
    recordId=$(echo "$record" | jq -r ".id")
    recordType=$(echo "$record" | jq -r ".type")
    recordName=$(echo "$record" | jq -r ".name")
    recordContent=$(echo "$record" | jq -r ".content")
    recordProxied=$(echo "$record" | jq -r ".proxied")

    if [[ $recordType == "A" && $recordContent != "$ipAddr" ]]; then
        updateDnsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${recordId}"
        res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$recordName\",\"content\":\"$ipAddr\",\"proxied\":$recordProxied}")
        resSuccess=$(echo "$res" | jq -r ".success")
        if [[ $resSuccess != "true" ]]; then
            echo "badauth"
            exit 1
        fi
    fi
done

# Fetch the IPv6 address if required
if [[ $ipv6 = "true" ]]; then
    ip6fetch=$(ip -6 addr show eth0 | grep -oP "$ipv6Regex" || true)
    ip6Addr=$(if [ -z "$ip6fetch" ]; then echo ""; else echo "$ip6fetch"; fi)
    if [[ -z "$ip6Addr" ]]; then
        ipv6="false"
    fi
fi

# Update all AAAA records with the new IPv6 address
if [[ $ipv6 = "true" && ! -z "$ip6Addr" ]]; then
    for record in $(echo "$resAAAA" | jq -c '.result[]'); do
        recordId=$(echo "$record" | jq -r ".id")
        recordType=$(echo "$record" | jq -r ".type")
        recordName=$(echo "$record" | jq -r ".name")
        recordContent=$(echo "$record" | jq -r ".content")
        recordProxied=$(echo "$record" | jq -r ".proxied")

        if [[ $recordType == "AAAA" && $recordContent != "$ip6Addr" ]]; then
            updateDnsApi="https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${recordId}"
            res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"AAAA\",\"name\":\"$recordName\",\"content\":\"$ip6Addr\",\"proxied\":$recordProxied}")
            resSuccess=$(echo "$res" | jq -r ".success")
            if [[ $resSuccess != "true" ]]; then
                echo "badauth"
                exit 1
            fi
        fi
    done
fi

echo "good"
