#!/usr/bin/env bash
# part of https://github.com/bkw777/notify-send.sh

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

SEND_SH="${0%/*}/notify-send.sh"
GDBUS_PIDFILE="${TMP}/${tself}.${$}.p"
GDBUS_MONITOR="monitor --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications"

abrt () { echo "${SELF}: $@" >&2 ; exit 1 ; }

# consume the command line
typeset -i ID="$1" ;shift
((ID)) || abrt "no notification id"
typeset -A a ;while (($#)) ;do a[$1]=$2 ;shift 2 ;done
((${#a[@]})) || abrt "no actions"

[[ "${DISPLAY}" ]] || abrt "no DISPLAY"
typeset -i i=0 p=0
set +H
shopt -s extglob

# kill obsolete monitors (now)
echo -n "${DISPLAY} ${ID} " > "${GDBUS_PIDFILE}"
for f in ${TMP}/${tself}.+([0-9]).p ;do
	[[ -s $f ]] || continue
	[[ $f -ot ${GDBUS_PIDFILE} ]] || continue
	read d i p x < $f
	[[ "$d" == "${DISPLAY}" ]] || continue
	((i==ID)) || continue
	((p>1)) || continue
	rm -f "$f"
	kill $p
done

# kill current monitor (on exit)
trap "conclude" 0
conclude () {
	${DEBUG} && set >&2
	[[ -s ${GDBUS_PIDFILE} ]] || exit 0
	read d i p x < "${GDBUS_PIDFILE}"
	rm -f "${GDBUS_PIDFILE}"
	((p>1)) || exit
	kill $p
}

# execute an invoked command
doit () {
	setsid -f ${a[${1}]} >&- 2>&- <&- &
	${EXPLICIT_CLOSE:-false} && "${SEND_SH}" -i ${ID} -d
}

# start the monitor
{
	gdbus ${GDBUS_MONITOR} & echo ${!} >> "${GDBUS_PIDFILE}"
} |while IFS=" :.(),'" read x x x x e x i x k x ;do
	((i==ID)) || continue
	${DEBUG} && printf 'event="%s" key="%s"\n' "$e" "$k" >&2
	case "$e" in
		"NotificationClosed") doit "close" ;;
		"ActionInvoked") doit "$k" ;;
	esac
	break
done
