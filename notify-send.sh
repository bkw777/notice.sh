#!/usr/bin/env bash
# notify-send.sh - replacement for notify-send with more features
# Copyright (C) 2015-2023 notify-send.sh authors (see AUTHORS file)
# https://github.com/bkw777/notify-send.sh

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# reference
# https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

SELF=${0##*/}
TMP=${XDG_RUNTIME_DIR:-/tmp}
${DEBUG_NOTIFY_SEND:=false} && {
	e="${TMP}/.${SELF}.${$}.e"
	echo "$0 debug logging to $e" >&2
	exec 2>"$e"
	set -x
	ARGV=("$0" "$@")
	trap "set >&2" 0
}

VERSION="1.2-bkw777"
ACTION_SH=${0%/*}/notify-action.sh
GDBUS_CALL=(call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

typeset -i i=0 ID=0 EXPIRE_TIME=-1 URGENCY=1
unset ID_FILE
AKEYS=()
ACMDS=()
HINTS=()
APP_NAME=${SELF}
PRINT_ID=false
EXPLICIT_CLOSE=false
SUMMARY=
BODY=
positional=false
summary_set=false
_r=

typeset -Ar HINT_TYPES=(
	[action-icons]=boolean
	[category]=string
	[desktop-entry]=string
	[image-path]=string
	[resident]=boolean
	[sound-file]=string
	[sound-name]=string
	[suppress-sound]=boolean
	[transient]=boolean
	[x]=int32
	[y]=int32
	[urgency]=byte
)

help () {
	cat <<EOF
Usage:
  notify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification

Help Options:
  -?|--help                         Show help options

Application Options:
  -u, --urgency=LEVEL               Specifies the urgency level (low, normal, critical).
  -t, --expire-time=TIME            Specifies the timeout in milliseconds at which to expire the notification.
  -f, --force-expire                Actively close the notification after the expire time, or after processing any action.
  -a, --app-name=APP_NAME           Specifies the app name for the icon.
  -i, --icon=ICON[,ICON...]         Specifies an icon filename or stock icon to display.
  -c, --category=TYPE[,TYPE...]     Specifies the notification category.
  -h, --hint=NAME:VALUE[:TYPE]      Specifies basic extra data to pass.
  -o, --action=LABEL:COMMAND        Specifies an action. Can be passed multiple times. LABEL is usually a button's label. COMMAND is a shell command executed when action is invoked.
  -l, --close-action=COMMAND        Specifies the action invoked when notification is closed.
  -p, --print-id                    Print the notification ID to the standard output.
  -r, --replace=ID                  Replace (update) an existing notification.
  -R, --replace-file=FILE           Store and load notification replace ID to/from this file.
  -s, --close=ID                    Close notification. With -R, get ID from -R file.
  -v, --version                     Version of the package.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html
EOF
}

abrt () { echo "${SELF}: $@" >&2 ; exit 1 ; }

notify_close () {
	i=$2 ;((i)) && sleep ${i:0:-3}.${i:$((${#i}-3))}
	gdbus ${GDBUS_CALL[@]} --method org.freedesktop.Notifications.CloseNotification -- "$1" >&-
}

process_urgency () {
	case "$1" in
		0|low) URGENCY=0 ;;
		1|normal) URGENCY=1 ;;
		2|critical) URGENCY=2 ;;
		*) abrt "Urgency values: 0 low 1 normal 2 critical" ;;
	esac
}

process_category () {
	local a c ;IFS=, a=($1)
	for c in "${a[@]}"; do
		make_hint string category "$c" && HINTS+=(${_r})
	done
}

make_hint () {
	_r= ;local n=$1 v=$2 t=${HINT_TYPES[$1]:-${3,,}}
	[[ $t = string ]] && v="\"$v\""
	_r="\"$n\":<$t $v>"
}

process_hint () {
	local a ;IFS=: a=($1)
	((${#a[@]}==2 || ${#a[@]}==3)) || abrt "Hint syntax: \"NAME:VALUE[:TYPE]\""
	make_hint "${a[0]}" "${a[1]}" ${a[2]} && HINTS+=(${_r})
}

process_action () {
	local a k ;IFS=: a=($1)
	((${#a[@]}==2)) || abrt "Action syntax: \"NAME:COMMAND\""
	k=${#AKEYS[@]}
	AKEYS+=("\"$k\",\"${a[0]}\"")
	ACMDS+=("$k" "${a[1]}")
}

# key=close:   key:command, no key:label
process_special_action () {
	[[ "$2" ]] || abrt "Command must not be empty"
	ACMDS+=("$1" "$2")
}

process_posargs () {
	[[ "$1" = -* ]] && ! ${positional} && abrt "Unknown option $1"
	${summary_set} && BODY=$1 || SUMMARY=$1 summary_set=true
}

while (($#)) ; do
	s= i=0
	case "$1" in
		-\?|--help)
			help
			exit 0
			;;
		-v|--version)
			echo "${SELF} ${VERSION}"
			exit 0
			;;
		-u|--urgency|--urgency=*)
			[[ "$1" = --urgency=* ]] && s=${1#*=} || { shift ;s=$1 ; }
			process_urgency "$s"
			;;
		-t|--expire-time|--expire-time=*)
			[[ "$1" = --expire-time=* ]] && EXPIRE_TIME=${1#*=} || { shift ;EXPIRE_TIME=$1 ; }
			;;
		-f|--force-expire|--explicit-close)
			export EXPLICIT_CLOSE=true
			;;
		-a|--app-name|--app-name=*)
			[[ "$1" = --app-name=* ]] && APP_NAME=${1#*=} || { shift ;APP_NAME=$1 ; }
			export APP_NAME
			;;
		-i|--icon|--icon=*)
			[[ "$1" = --icon=* ]] && ICON=${1#*=} || { shift ;ICON=$1 ; }
			;;
		-c|--category|--category=*)
			[[ "$1" = --category=* ]] && s=${1#*=} || { shift ;s=$1 ; }
			process_category "$s"
			;;
		-h|--hint|--hint=*)
			[[ "$1" = --hint=* ]] && s=${1#*=} || { shift ;s=$1 ; }
			process_hint "$s"
			;;
		-o|--action|--action=*)
			[[ "$1" == --action=* ]] && s=${1#*=} || { shift ;s=$1 ; }
			process_action "$s"
			;;
		-l|--close-action|--close-action=*)
			[[ "$1" == --close-action=* ]] && s=${1#*=} || { shift ;s=$1 ; }
			process_special_action close "$s"
			;;
		-p|--print-id)
			PRINT_ID=true
			;;
		-r|--replace|--replace=*)
			[[ "$1" = --replace=* ]] && ID=${1#*=} || { shift ;ID=$1 ; }
			;;
		-R|--replace-file|--replace-file=*)
			[[ "$1" = --replace-file=* ]] && ID_FILE=${1#*=} || { shift ;ID_FILE=$1 ; }
			[[ -s ${ID_FILE} ]] && read ID < "${ID_FILE}"
			;;
		-s|--close|--close=*)
			[[ "$1" = --close=* ]] && i=${1#*=} || { shift ;i=$1 ; }
			((i<1)) && ((ID)) && i=${ID}
			((i)) && notify_close $i ${EXPIRE_TIME}
			exit $?
			;;
		--)
			positional=true
			;;
		*)
			process_posargs "$1"
			;;
	esac
	shift
done

# build the actions & hints strings
a= ;for s in "${AKEYS[@]}" ;do a+=,$s ;done ;a=${a:1}
make_hint urgency "${URGENCY}" ;h=${_r}
for s in "${HINTS[@]}" ;do h+=,$s ;done

# send the dbus message, collect the notification ID
typeset -i OLD_ID=${ID} NEW_ID=0
s=$(gdbus ${GDBUS_CALL[@]} --method org.freedesktop.Notifications.Notify -- \
	"${APP_NAME}" ${ID} "${ICON}" "${SUMMARY}" "${BODY}" \
	"[$a]" "{$h}" "${EXPIRE_TIME}")

# process the ID
s=${s%,*} NEW_ID=${s#* }
((NEW_ID)) || abrt "invalid notification ID from gdbus"
((OLD_ID)) || ID=${NEW_ID}
[[ "${ID_FILE}" ]] && ((OLD_ID<1)) && echo ${ID} > "${ID_FILE}"
${PRINT_ID} && echo ${ID}

# bg task to monitor dbus and perform the actions
((${#ACMDS[@]})) && setsid -f "${ACTION_SH}" ${ID} "${ACMDS[@]}" >&- 2>&- &

# bg task to wait expire time and then actively close notification
${EXPLICIT_CLOSE} && ((EXPIRE_TIME)) && setsid -f "$0" -t ${EXPIRE_TIME} -s ${ID} >&- 2>&- <&- &
