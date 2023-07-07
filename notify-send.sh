#!/usr/bin/env bash
# notify-send.sh - replacement for notify-send
# https://github.com/bkw777/notify-send.sh
# reference
# https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

SELF="${0##*/}"
tself="${0//\//_}"
TMP="${XDG_RUNTIME_DIR:-/tmp}"
${DEBUG:=false} && {
	e="${TMP}/${tself}.${$}.e"
	echo "$0 debug logging to $e" >&2
	exec 2>"$e"
	set -x
	ARGV=("$0" "$@")
	trap "set >&2" 0
}

VERSION="1.3-bkw777"
ACTION_SH="${0%/*}/notify-action.sh"
GDBUS_CALL=(call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

typeset -i i=0 ID=0 EXPIRE_TIME=-1
unset ID_FILE
AKEYS=()
ACMDS=()
HINTS=()
APP_NAME="${SELF}"
ICON=
PRINT_ID=false
EXPLICIT_CLOSE=false
DISMISS=false
TITLE=
BODY=
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

typeset -r ifs="$IFS"

help () {
	cat <<EOF
Usage:
  ${SELF} [OPTION...] [TITLE] [BODY]

Options:
  -N, --app-name=APP_NAME           Specify the formal name of application sending the notification.
                                    ex: "Mullvad VPN"

  -n, --icon=ICON                   Specify an image or icon to display.
                                    * installed *.desktop name   ex: "firefox"
                                    * standard themed icon name  ex: "dialog-information"
                                      https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                    * path to image file

  -h, --hint=NAME:VALUE[:TYPE]      Specify extra data. Can be given multiple times. Examples:
                                    --hint=urgency:0
                                    --hint=category:device.added
                                    --hint=transient:false
                                    --hint=desktop-entry:firefox
                                    --hint=image-path:/path/to/file.png|jpg|svg|...

  -a, --action=[LABEL:]COMMAND      Specify an action button. Can be given multiple times.
                                    LABEL is a buttons label.
                                    COMMAND is a shell command to run when LABEL button is pressed.
                                    If LABEL is absent, COMMAND is run when the notification is dismissed.

  -p, --print-id                    Print the notification ID.

  -i, --id=<ID|@FILENAME>           Specify the ID of an existing notification to update or dismiss.
                                    If "@FILENAME", read ID from & write ID to FILENAME.

  -t, --expire-time=TIME            Specify the time in seconds for the notification to live.
                                    -1 = server default, 0 = never expire, default = -1

  -f, --force-expire                Actively close the notification after the expire time,
                                    or after processing any of it's actions.

  -d, --dismiss                     Close notification. (requires --id)

  -v, --version                     Display script version.

  -?, --help                        This help.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html
EOF
}

abrt () { echo "${SELF}: $@" >&2 ; exit 1 ; }

_dismiss () {
	((EXPIRE_TIME>0)) && sleep ${EXPIRE_TIME}
	set -x
	gdbus ${GDBUS_CALL[@]} --method org.freedesktop.Notifications.CloseNotification -- ${ID} >&-
	[[ -s ${ID_FILE} ]] && > "${ID_FILE}"
	exit
}

_hint () {
	local a ;IFS=: a=($1) ;IFS="$ifs"
	((${#a[@]}==2 || ${#a[@]}==3)) || abrt "Hint syntax: \"NAME:VALUE[:TYPE]\""
	local n="${a[0]}" v="${a[1]}" t="${a[2]}"
	t=${HINT_TYPES[$n]:-${t,,}}
	[[ $t = string ]] && v="\"$v\""
	HINTS+=("\"$n\":<$t $v>")
}

_action () {
	local a k ;IFS=: a=($1) ;IFS="$ifs"
	case ${#a[@]} in
		1) k=close a=("" ${a[0]}) ;;
		2) k=${#AKEYS[@]} ;AKEYS+=("\"$k\",\"${a[0]}\"") ;;
		*) abrt "Action syntax: \"[NAME:]COMMAND\"" ;;
	esac
	ACMDS+=("$k" "${a[1]}")
}

#### parse the commandline ####################################################

# Support "-x foo", "--xoption foo", and "--xoption=foo" with built-in getopts
# by first just normalizing the long forms to the short form.

# convert all "--foo=bar" to "--foo bar"
typeset a=()
for x in "$@"; do
	case "$x" in
		--*=*) a+=("${x/=/ }") ;;
		*) a+=("$x") ;;
	esac
done
# convert all "--xoption" to "-x"
for ((i=0;i<${#a[@]};i++)) {
	case "${a[i]}" in
		--app-name)     a[i]='-N' ;;
		--icon)         a[i]='-n' ;;
		--hint)         a[i]='-h' ;;
		--action)       a[i]='-a' ;;
		--print-id)     a[i]='-p' ;;
		--id)           a[i]='-i' ;;
		--expire-time)  a[i]='-t' ;;
		--force-expire) a[i]='-f' ;;
		--dismiss)      a[i]='-d' ;;
		--version)      a[i]='-v' ;;
		--help)         a[i]='-?' ;;
		--*)            a[i]='-!' ;;
	esac
}
set -- "${a[@]}"
(($#)) || set -- '-?'
# parse the now normalized all-short options
OPTIND=1
while getopts 'N:n:h:a:pi:t:fdv?' x ;do
	case "$x" in
		N) APP_NAME="$OPTARG" ;;
		n) ICON="$OPTARG" ;;
		h) _hint "$OPTARG" ;;
		a) _action "$OPTARG" ;;
		p) PRINT_ID=true ;;
		i) [[ ${OPTARG:0:1} == '@' ]] && ID_FILE="${OPTARG:1}" || ID=$OPTARG ;;
		t) EXPIRE_TIME=$OPTARG ;;
		f) export EXPLICIT_CLOSE=true ;;
		d) DISMISS=true ;;
		v) echo "${SELF} ${VERSION}" ;exit 0 ;;
		'?') help ;exit 0 ;;
		*) help ;exit 1 ;;
	esac
done
shift $((OPTIND-1))
TITLE="$1" ;shift
BODY="$1" ;shift

# if we don't have an ID, try ID_FILE
((ID<1)) && [[ -s "${ID_FILE}" ]] && read ID < "${ID_FILE}"

# if we got a dismiss command, then do that now and exit
((ID)) && ${DISMISS} && _dismiss

# build the actions & hints strings
a= ;for s in "${AKEYS[@]}" ;do a+=",$s" ;done ;a="${a:1}"
h= ;for s in "${HINTS[@]}" ;do h+=",$s" ;done ;h="${h:1}"
typeset -i t=${EXPIRE_TIME} ;((t>0)) && ((t=t*1000))

# send the dbus message, collect the notification ID
typeset -i OLD_ID=${ID} NEW_ID=0
s=$(gdbus ${GDBUS_CALL[@]} --method org.freedesktop.Notifications.Notify -- \
	"${APP_NAME}" ${ID} "${ICON}" "${TITLE}" "${BODY}" "[$a]" "{$h}" "${t}")

# process the ID
s="${s%,*}" NEW_ID="${s#* }"
((NEW_ID)) || abrt "invalid notification ID from gdbus"
((OLD_ID)) || ID=${NEW_ID}
[[ "${ID_FILE}" ]] && ((OLD_ID<1)) && echo ${ID} > "${ID_FILE}"
${PRINT_ID} && echo ${ID}

# background task to monitor dbus and perform the actions
((${#ACMDS[@]})) && setsid -f "${ACTION_SH}" ${ID} "${ACMDS[@]}" >&- 2>&- &

# background task to wait expire time and then actively dismiss the notification
${EXPLICIT_CLOSE} && ((EXPIRE_TIME)) && setsid -f "$0" -t ${EXPIRE_TIME} -i ${ID} -d >&- 2>&- <&- &
