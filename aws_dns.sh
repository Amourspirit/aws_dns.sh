#!/bin/bash

# MIT License
#
# Copyright (c) 2020 Paul Moss
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#
# SOFTWARE.
# Author: Paul Moss
# Created 2020-06-30
# Github: https://github.com/Amourspirit/aws_dns.sh
# File Name: aws_dns.sh
# Version 1.0.0
#Variable Declaration - Change These
HOSTED_ZONE_FILE="$HOME/.aws_dns/zone"
CONFIG_FILE="$HOME/.aws_dns/config.cfg"

# function: _trim
# Param 1: the variable to _trim whitespace from
# Usage:
#   while read line; do
#       if [[ "$line" =~ ^[^#]*= ]]; then
#           setting_name=$(_trim "${line%%=*}");
#           setting_value=$(_trim "${line#*=}");
#           SCRIPT_CONF[$setting_name]=$setting_value
#       fi
#   done < "$TMP_CONFIG_COMMON_FILE"
function _trim () {
    local var=$1;
    var="${var#"${var%%[![:space:]]*}"}";   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}";   # remove trailing whitespace characters
    echo -n "$var";
}
# Test if a value is in the format of a valid IP4 Address
# Usage:
# if [[ $(_ip_valid $IP) ]]; then
#   echo 'IP is valid'
# else
#   echo 'Invalid IP'
# fi
function _ip_valid() {
	_ip="$1"
	if [[ $_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		echo 1
	fi
}

# Get INI _section
function ReadINI_Sections(){
  local filename="$1"
  awk '{ if ($1 ~ /^\[/) _section=tolower(gensub(/\[(.+)\]/,"\\1",1,$1)); configuration[_section]=1 } END {for (key in configuration) { print key} }' ${filename}
}

# Get/Set all INI _sections
function GetINI_Sections(){
  local filename="$1"

  _sections="$(ReadINI_Sections $filename)"
	for _section in $_sections; do
		array_name="configuration_${_section}"
		declare -g -A ${array_name}
	done
	eval $(awk -F= '{ 
					if ($1 ~ /^\[/)
						_section=tolower(gensub(/\[(.+)\]/,"\\1",1,$1))
					else if ($1 !~ /^$/ && $1 !~ /^;/) {
						gsub(/^[ \t]+|[ \t]+$/, "", $1);
						gsub(/[\[\]]/, "", $1);
						gsub(/^[ \t]+|[ \t]+$/, "", $2);
					if (configuration[_section][$1] == "")
						configuration[_section][$1]=$2
					else
						configuration[_section][$1]=configuration[_section][$1]" "$2}
					}
					END {
						for (_section in configuration)
							for (key in configuration[_section])
								print "configuration_"_section"[\""key"\"]=\""configuration[_section][key]"\";"
					}' ${filename}
		)
}

if [[ ! -r "$CONFIG_FILE" ]]; then
	echo "Unable to read file: $CONFIG_FILE"
	exit 1
fi
if [[ ! -r "$HOSTED_ZONE_FILE" ]]; then
	echo "Unable to read file: $HOME/.aws_dns/zone"
	exit 1
fi
HOSTED_ZONE_ID="$(cat $HOSTED_ZONE_FILE)"
HOSTED_ZONE_ID=$(_trim "$HOSTED_ZONE_ID")
if [[ -z "$HOSTED_ZONE_ID" ]]; then
	echo -n 'Empyt hosted zone file. Place the value of your hosted zone in file: '
	echo "$HOSTED_ZONE_FILE"
	exit 1
fi
#get current IP address
IP=$(wget -qT 20 -O - "https://checkip.amazonaws.com/")
if ! [[ $(_ip_valid $IP) ]]; then
	echo 'Not a valid IP4 Address'
	exit 1
fi

GetINI_Sections "$CONFIG_FILE"
# echo 'Config Read'
for _section in $(ReadINI_Sections "$CONFIG_FILE"); do
	# echo "[${_section}]"
	# create an array that contains configuration values
	# put values that need to be evaluated using eval in single quotes
	typeset -A SCRIPT_CONF # init array
	SCRIPT_CONF=( # set default values in config array
		[domain]=''
		[type]='A'
		[ttl]=60
	)
	for key in $(eval echo \$\{'!'configuration_${_section}[@]\}); do
		SCRIPT_CONF["${key}"]="$(eval echo \$\{configuration_${_section}[$key]\})"
	done
	if [[ ! -z "${SCRIPT_CONF[domain]}" ]]; then
		if [[ "${SCRIPT_CONF[domain]}" != *. ]]; then
			# add . to end of domain name if it does not exist already
			SCRIPT_CONF[domain]="${SCRIPT_CONF[domain]}."
		fi

		#get current
		aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID | \
		jq -r '.ResourceRecordSets[] | select (.Name == "'"${SCRIPT_CONF[domain]}"'") | select (.Type == "'"${SCRIPT_CONF[type]}"'") | .ResourceRecords[0].Value' > "/tmp/current_${_section}_route53_value"

		# cat "/tmp/current_${_section}_route53_value"

		#check if IP is different from Route 53
		if grep -Fxq "$IP" "/tmp/current_${_section}_route53_value"; then
			echo "IP Has Not Changed, Exiting"
			# exit 1
			continue
		fi

		echo "IP Changed, Updating Records"

#prepare route 53 payload
# IFS='' read -r -d '' String <<"EOF"
cat > /tmp/route53_changes.json << EOF
{
      "Comment":"Updated From DDNS Shell Script",
      "Changes":[
        {
          "Action":"UPSERT",
          "ResourceRecordSet":{
            "ResourceRecords":[
              {
                "Value":"$IP"
              }
            ],
            "Name":"${SCRIPT_CONF[domain]}",
			"Type":"${SCRIPT_CONF[type]}",
			"TTL":${SCRIPT_CONF[ttl]}
          }
        }
      ]
    }
EOF
		#update records
		aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///tmp/route53_changes.json >> /dev/null
	fi
done
exit 0
