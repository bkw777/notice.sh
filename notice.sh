#!/usr/bin/env bash
# notice.sh - desktop notification client
# Brian K. White <b.kenyon.w@gmail.com>
# https://github.com/bkw777/notice.sh
# https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html
set +H

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

VERSION="2.0"
GDBUS_ARGS=(--session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)
GDBUS_PIDFILE="${TMP}/${tself}.${$}.p"
GDBUS_PIDFILES="${TMP}/${tself}.+([0-9]).p"

typeset -i i=0 p=0 ID=0 EXPIRE_TIME=-1 KI=0
typeset -a ACMDS=()
unset ID_FILE ICON TITLE BODY AKEYS HINTS
APP_NAME="${SELF}"
PRINT_ID=false
EXPLICIT_CLOSE=false
DISMISS=false
ACTION_DAEMON=false
typeset -A c=()

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
  ${SELF} [OPTIONS...] [BODY]

Options:
  -N, --app-name=APP_NAME           Specify the formal name of application sending the notification.
                                    ex: "Mullvad VPN"

  -n, --icon=ICON                   Specify an image or icon to display.
                                    * installed *.desktop name   ex: "firefox"
                                    * standard themed icon name  ex: "dialog-information"
                                      https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html)
                                    * path to image file

  -T, --title=TITLE                 Title

  -B, --body=BODY                   Message body
                                    If both this and trailing non-option args are supplied,
                                    this takes precedence and the trailing args will be ignored

  -h, --hint=NAME:VALUE[:TYPE]      Specify extra data. Can be given multiple times. Examples:
                                    --hint=urgency:0
                                    --hint=category:device.added
                                    --hint=transient:false
                                    --hint=desktop-entry:firefox
                                    --hint=image-path:/path/to/file.png|jpg|svg|...
  
  -a, --action=[LABEL:]COMMAND      Specify an action button. Can be given multiple times.
                                    LABEL is a buttons label.
                                    COMMAND is a shell command to run when LABEL button is pressed.
                                    If LABEL: is absent, COMMAND is run when the notification closes (whether clicked or expired).
                                    If LABEL is "" or '', COMMAND is the "default-action", run only when/if the notification is clicked.
                                    Not all notification daemons support default-action, so this may just create a normal button
                                    with a literal "" label.

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

########################################################################
# action daemon
#

# TODO: Can we make this more elegant by just sending a signal
# to the parent process, it traps the signal to exit itself,
# and it's child gdbus process exits itself naturally on HUP?

ad_kill_obsolete_daemons () {
	shopt -s extglob
	for f in ${GDBUS_PIDFILES} ;do
		[[ -s $f ]] || continue
		[[ $f -ot ${GDBUS_PIDFILE} ]] || continue
		read d i p x < $f
		[[ "$d" == "${DISPLAY}" ]] || continue
		((i==ID)) || continue
		((p>1)) || continue
		rm -f "$f"
		kill $p
	done
}

ad_kill_current_daemon () {
	${DEBUG} && set >&2
	[[ -s ${GDBUS_PIDFILE} ]] || exit 0
	read d i p x < "${GDBUS_PIDFILE}"
	rm -f "${GDBUS_PIDFILE}"
	((p>1)) || exit
	kill $p
}

ad_run () {
	setsid -f ${c[${1}]} >&- 2>&- <&-
	${EXPLICIT_CLOSE} && "$0" -i ${ID} -d
}

action_daemon () {
	((ID)) || abrt "no notification id"
	while (($#)) ;do c[$1]="$2" ;shift 2 ;done
	((${#c[@]})) || abrt "no actions"
	[[ "${DISPLAY}" ]] || abrt "no DISPLAY"
	echo -n "${DISPLAY} ${ID} " > "${GDBUS_PIDFILE}"
	ad_kill_obsolete_daemons
	trap "ad_kill_current_daemon" 0
	{
		gdbus monitor ${GDBUS_ARGS[@]} -- & echo ${!} >> "${GDBUS_PIDFILE}"
	} |while IFS=" :.(),'" read x x x x e x i x k x ;do
		((i==ID)) || continue
		${DEBUG} && printf 'event="%s" key="%s"\n' "$e" "$k" >&2
		case "$e" in
			"NotificationClosed") ad_run "close" ;;
			"ActionInvoked") ad_run "$k" ;;
		esac
		break
	done
	exit
}

#
# action daemon
########################################################################


dismiss () {
	((ID)) || abrt "no ID"
	((EXPIRE_TIME>0)) && sleep ${EXPIRE_TIME}
	gdbus call ${GDBUS_ARGS[@]} --method org.freedesktop.Notifications.CloseNotification -- ${ID} >&-
	[[ -s ${ID_FILE} ]] && > "${ID_FILE}"
	exit
}

add_hint () {
	local a ;IFS=: a=($1) ;IFS="$ifs"
	((${#a[@]}==2 || ${#a[@]}==3)) || abrt "syntax: -h or --hint=\"NAME:VALUE[:TYPE]\""
	local n="${a[0]}" v="${a[1]}" t="${a[2]}"
	t=${HINT_TYPES[$n]:-${t,,}}
	[[ $t = string ]] && v="\"$v\""
	((${#HINTS})) && HINTS+=,
	HINTS+="\"$n\":<$t $v>"
}

add_action () {
	local a k ;IFS=: a=($1) ;IFS="$ifs"
	case ${#a[@]} in
		1) k=close a=("" "${a[0]}") ;;
		2) k=$((KI++)) ;((${#AKEYS})) && AKEYS+=, ;AKEYS+="\"${k}\",\"${a[0]}\"" ;;
		*) abrt "syntax: -a or --action=\"[NAME:]COMMAND\"" ;;
	esac
	ACMDS+=("${k}" "${a[1]}")
}


########################################################################
# parse the commandline
#

# Convert any "--xoption foo" and "--xoption=foo"
# to their equivalent "-x foo", so that we can use the built-in
# getopts yet still support long options

# convert all "--foo=bar" to "--foo bar"
a=()
for x in "$@"; do
	case "$x" in
		--*=*) a+=("${x%%=*}" "${x#*=}") ;;
		*) a+=("$x") ;;
	esac
done
# convert all "--xoption" to "-x"
for ((i=0;i<${#a[@]};i++)) {
	case "${a[i]}" in
		--app-name)     a[i]='-N' ;;
		--icon)         a[i]='-n' ;;
		--title)        a[i]='-T' ;;
		--body)         a[i]='-B' ;;
		--hint)         a[i]='-h' ;;
		--action)       a[i]='-a' ;;
		--print-id)     a[i]='-p' ;;
		--id)           a[i]='-i' ;;
		--expire-time)  a[i]='-t' ;;
		--force-expire) a[i]='-f' ;;
		--dismiss)      a[i]='-d' ;;
		--version)      a[i]='-v' ;;
		--help)         a[i]='-?' ;;
		--?*)           a[i]='-!' ;;
		--)             break ;;
	esac
}
set -- "${a[@]}"
# parse the now-normalized all-short options
OPTIND=1
while getopts 'N:n:T:B:h:a:pi:t:fdv%?!' x ;do
	case "$x" in
		N) APP_NAME="$OPTARG" ;;
		n) ICON="$OPTARG" ;;
		T) TITLE="$OPTARG" ;;
		B) BODY="$OPTARG" ;;
		a) add_action "$OPTARG" ;;
		h) add_hint "$OPTARG" ;;
		p) PRINT_ID=true ;;
		i) [[ ${OPTARG:0:1} == '@' ]] && ID_FILE="${OPTARG:1}" || ID=$OPTARG ;;
		t) EXPIRE_TIME=$OPTARG ;;
		f) EXPLICIT_CLOSE=true ;;
		d) DISMISS=true ;;
		v) echo "${SELF} ${VERSION}" ;exit 0 ;;
		%) ACTION_DAEMON=true ;;
		'?') help ;exit 0 ;;
		*) help ;exit 1 ;;
	esac
done
shift $((OPTIND-1))

# if we don't have an ID, try ID_FILE
((ID<1)) && [[ -s "${ID_FILE}" ]] && read ID < "${ID_FILE}"

# if we got a dismiss command, then do that now and exit
${DISMISS} && dismiss

# if daemon mode, divert to that
${ACTION_DAEMON} && action_daemon "$@"

########################################################################
# main
#

((${#BODY}<1)) && (($#)) && BODY="$@"
typeset -i t=${EXPIRE_TIME} ;((t>0)) && ((t=t*1000))

# send the dbus message, collect the notification ID
s=$(gdbus call ${GDBUS_ARGS[@]} --method org.freedesktop.Notifications.Notify -- \
	"${APP_NAME}" ${ID} "${ICON}" "${TITLE}" "${BODY}" "[${AKEYS}]" "{${HINTS}}" "${t}")

# process the collected ID
s="${s%,*}" ID="${s#* }"
((ID)) || abrt "invalid notification ID from gdbus"
[[ "${ID_FILE}" ]] && echo ${ID} > "${ID_FILE}"
${PRINT_ID} && echo ${ID}

# background task to monitor dbus and perform the actions
s= ;${EXPLICIT_CLOSE} && s='-f'
((${#ACMDS[@]})) && setsid -f "$0" -i ${ID} ${s} -% "${ACMDS[@]}" >&- 2>&- <&-

# background task to wait expire time and then actively dismiss the notification
${EXPLICIT_CLOSE} && ((EXPIRE_TIME)) && setsid -f "$0" -t ${EXPIRE_TIME} -i ${ID} -d >&- 2>&- <&-
