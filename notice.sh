#!/usr/bin/env bash
# notice.sh - desktop notification client
# Brian K. White <b.kenyon.w@gmail.com>
# https://github.com/bkw777/notice.sh
# license GPL3
# https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html
set +H
shopt -u extglob

SELF="${0##*/}"
tself="${0//\//_}"
TMP="${XDG_RUNTIME_DIR:-/tmp}"
${DEBUG:=false} && {
	export DEBUG
	e="${TMP}/${tself}.${$}.e"
	echo "$0 debug logging to $e" >&2
	exec 2>"$e"
	set -x
	ARGV=("$0" "$@")
	trap "set >&2" 0
}

VERSION="2.2"
GDBUS_ARGS=(--session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications)

typeset -i i ID=0 TTL=-1 KI=0
typeset -a a ACMDS=()
unset ID_FILE ICON SUMMARY BODY AKEYS HINTS
APP_NAME="${SELF}"
FORCE_CLOSE=false
CLOSE=false
ACTION_DAEMON=false

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

typeset -r ifs="${IFS}"

help () {
	echo "
${SELF} - desktop notification client
Version ${VERSION}
https://github.com/bkw777/notice.sh

Usage:
  ${SELF} [OPTIONS...] [--] [SUMMARY]

Options:
  -N, --app-name=APP_NAME           Formal name of the application sending the notification
                                    --app-name=\"Super De-Duper\"

  -n, --icon=ICON                   Icon or image to display
                                    --icon=firefox             - basename of *.desktop file
                                    --icon=dialog-information  - standard themed icon name
                                      https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                    --icon=/path/to/file.svg   - or png, jpg, etc

  -s, --summary=SUMMARY             Title message
                                    If both this and trailing non-option args are supplied,
                                    this takes precedence and the trailing args are ignored.

  -b, --body=BODY                   Message body                        (note)

  -h, --hint=NAME:VALUE[:TYPE]      Extra data
                                    Can be given multiple times.
                                    --hint=urgency:0                    (note)
                                    --hint=category:mail                (note)
                                    --hint=transient:false
                                    --hint=desktop-entry:firefox
                                    --hint=image-path:/path/to/file.png|jpg|svg|...

                                    TYPE is the data type like string or boolean
                                    and can usually be omitted.

  -a, --action=[[LABEL]:]COMMAND    Action
                                    Can be given multiple times.
                                    LABEL is a label for a button.
                                    COMMAND is a shell command to run when action is invoked.

               LABEL:COMMAND        button-action
                                    COMMAND is run if the LABEL button is pressed

               :COMMAND             default-action                      (note)
                                    COMMAND is run if the notification is clicked

               COMMAND              close-action
                                    COMMAND is run when the notification closes (whether clicked or expired)
                                    Use in combination with -t0 (never self-expire) to get a behavior
                                    similar to default-action on servers that don't support default-action.

  -i, --id=ID                       ID of an existing notification to update or close
  -i, --id=@FILENAME                write ID to & read ID from FILENAME
                                    If --id is not used, then ID is printed to stdout.

  -t, --ttl=SECONDS                 Time-To-Live, in seconds, before the notification closes itself
                                    0 = forever

  -f, --force-close                 Actively close the notification after TTL seconds,
                                    or after processing any of it's actions

  -c, --close                       Close notification - requires --id

  -v, --version                     Display script version

  -?, --help                        This help

  --                                End option parsing
                                    Anything after this is treated as literal SUMMARY text,
                                    even if it looks like an option.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

(note) Not all servers support all features. Some options may do nothing on your server.
"
}

abrt () { echo "${SELF}: $@" >&2 ; exit 1 ; }

########################################################################
# action daemon
#

# TODO: Can we make this more elegant by just sending a signal
# to the parent process, it traps the signal to exit itself,
# and it's child gdbus process exits itself naturally on HUP?

kill_obsolete_daemons () {
	local f d x n ;local -i i p
	n=$1 ;shift
	for f in $@ ;do
		[[ -s $f ]] || continue
		[[ $f -ot $n ]] || continue
		read d i p x < $f
		[[ "$d" == "${DISPLAY}" ]] || continue
		((i==ID)) || continue
		((p>1)) || continue
		rm -f $f
		kill $p
	done
}

kill_current_daemon () {
	[[ -s $1 ]] || exit 0
	local d x ;local -i i p
	read d i p x < $1
	rm -f $1
	((p>1)) || exit 0
	kill $p
}

run () {
	(($#)) && eval setsid -f $@ >&- 2>&- <&-
	${FORCE_CLOSE} && "$0" -i ${ID} -c
}

action_daemon () {
	((ID)) || abrt "no ID"
	local -A c=()
	while (($#)) ;do c[$1]="$2" ;shift 2 ;done
	((${#c[@]})) || abrt "no actions"
	[[ "${DISPLAY}" ]] || abrt "no DISPLAY"
	local f="${TMP}/${tself}.${$}.p" l="${TMP}/${tself}.+([0-9]).p"
	echo -n "${DISPLAY} ${ID} " > $f
	shopt -s extglob
	kill_obsolete_daemons $f $l
	shopt -u extglob
	trap "kill_current_daemon $f" 0
	local e k x ;local -i i
	{
		gdbus monitor ${GDBUS_ARGS[@]} -- & echo ${!} >> $f
	} |while IFS=" :.(),'" read x x x x e x i x k x ;do
		((i==ID)) || continue
		${DEBUG} && printf 'event="%s" key="%s"\n' "$e" "$k" >&2
		case "$e" in
			"NotificationClosed") run "${c[close]}" ;;
			"ActionInvoked") run "${c[$k]}" ;;
		esac
		break
	done
	exit 0
}

#
# action daemon
########################################################################

close_notification () {
	((ID)) || abrt "no ID"
	((TTL>0)) && sleep ${TTL}
	gdbus call ${GDBUS_ARGS[@]} --method org.freedesktop.Notifications.CloseNotification -- ${ID} >&-
	[[ ${ID_FILE} ]] && rm -f "${ID_FILE}"
	exit 0
}

add_hint () {
	local -a a ;IFS=: a=($1) ;IFS="${ifs}"
	((${#a[@]}==2 || ${#a[@]}==3)) || abrt "syntax: -h or --hint=\"NAME:VALUE[:TYPE]\""
	local n="${a[0]}" v="${a[1]}" t="${a[2],,}"
	: ${t:=${HINT_TYPES[$n]}}
	[[ $t = string ]] && v="\"$v\""
	((${#HINTS})) && HINTS+=,
	HINTS+="\"$n\":<$t $v>"
}

add_action () {
	local k ;local -a a ;IFS=: a=($1) ;IFS="${ifs}"
	case ${#a[@]} in
		1) k=close a=("" "${a[0]}") ;;
		2) ((${#a[0]})) && k=$((KI++)) || k=default ;((${#AKEYS})) && AKEYS+=, ;AKEYS+="\"$k\",\"${a[0]}\"" ;;
		*) abrt "syntax: -a or --action=\"[[LABEL]:]COMMAND\"" ;;
	esac
	ACMDS+=("$k" "${a[1]}")
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
		--summary)      a[i]='-s' ;;
		--body)         a[i]='-b' ;;
		--hint)         a[i]='-h' ;;
		--action)       a[i]='-a' ;;
		--id)           a[i]='-i' ;;
		--ttl)          a[i]='-t' ;;
		--force-close)  a[i]='-f' ;;
		--close)        a[i]='-c' ;;
		--version)      a[i]='-v' ;;
		--help)         a[i]='-?' ;;
		--?*)           a[i]='-!' ;;
		--)             break ;;
	esac
}
set -- "${a[@]}"
# parse the now-normalized all-short options
OPTIND=1
while getopts 'N:n:s:b:h:a:i:t:fcv%?!' x ;do
	case "$x" in
		N) APP_NAME="${OPTARG}" ;;
		n) ICON="${OPTARG}" ;;
		s) SUMMARY="${OPTARG}" ;;
		b) BODY="${OPTARG}" ;;
		a) add_action "${OPTARG}" ;;
		h) add_hint "${OPTARG}" ;;
		i) [[ ${OPTARG:0:1} == '@' ]] && ID_FILE="${OPTARG:1}" || ID=${OPTARG} ;;
		t) TTL=${OPTARG} ;;
		f) FORCE_CLOSE=true ;;
		c) CLOSE=true ;;
		v) echo "${SELF} ${VERSION}" ;exit 0 ;;
		%) ACTION_DAEMON=true ;;
		'?') help ;exit 0 ;;
		*) help ;exit 1 ;;
	esac
done
shift $((OPTIND-1))

# if we don't have an ID, try ID_FILE
((ID<1)) && [[ -s "${ID_FILE}" ]] && read ID < "${ID_FILE}"

########################################################################
# modes
#

# if we got a close command, then do that now and exit
${CLOSE} && close_notification

# if daemon mode, divert to that
${ACTION_DAEMON} && action_daemon "$@"

########################################################################
# main
#

((${#SUMMARY}<1)) && (($#)) && SUMMARY="$@"
typeset -i t=${TTL} ;((t>0)) && ((t=t*1000))

# send the dbus message, collect the notification ID
x=$(gdbus call ${GDBUS_ARGS[@]} --method org.freedesktop.Notifications.Notify -- \
	"${APP_NAME}" ${ID} "${ICON}" "${SUMMARY}" "${BODY}" "[${AKEYS}]" "{${HINTS}}" "$t")

# process the collected ID
x="${x%,*}" ID="${x#* }"
((ID)) || abrt "invalid notification ID from gdbus"
[[ ${ID_FILE} ]] && echo ${ID} > "${ID_FILE}" || echo ${ID}

# background task to monitor dbus and perform the actions
x= ;${FORCE_CLOSE} && x='-f'
((${#ACMDS[@]})) && setsid -f "$0" -i ${ID} $x -% "${ACMDS[@]}" >&- 2>&- <&-

# background task to wait TTL seconds and then actively close the notification
${FORCE_CLOSE} && ((TTL>0)) && setsid -f "$0" -t ${TTL} -i ${ID} -c >&- 2>&- <&-

exit 0
