#!/usr/bin/env bash
# notice.sh - desktop notification client
# Brian K. White <b.kenyon.w@gmail.com>
# Daniel Rudolf <https://www.daniel-rudolf.de>
# https://github.com/bkw777/notice.sh
# license GPL3

SELF="${0##*/}"
tself="${0//\//_}"
TMP="${XDG_RUNTIME_DIR:-/tmp}"
VERSION="2.2"

typeset -i TTL=-1
typeset -a ARGS=()
AFIFO="${TMP}/${tself}.${$}.w"
AI=0
AV=
WAIT=false
PRINT_ID=false

typeset -r ifs="${IFS}"

help () {
	echo "
${SELF} - desktop notification client (notify-send wrapper for notice.sh)
Version ${VERSION}
https://github.com/bkw777/notice.sh

Usage:
  ${SELF} [OPTIONS...] [--] [SUMMARY] [BODY]

Options:
  -a, --app-name=APP_NAME              Formal name of the application sending the notification
                                       --app-name=\"Super De-Duper\"

  -i, --icon=ICON                      Icon or image to display
                                       --icon=firefox             - basename of *.desktop file
                                       --icon=dialog-information  - standard themed icon name
                                         https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                       --icon=/path/to/file.svg   - or png, jpg, etc

  -u, --urgency=URGENCY                Notification urgency level          (note)
                                       URGENCY is either low, normal, or critical.

  -e, --transient                      Show a transient notification
                                       Transient notifications by-pass the server's persistence capability,
                                       if any. And so it won't be preserved until the user acknowledges it.

  -c, --category=TYPE[,TYPE...]        Notification category               (note)

  -h, --hint=TYPE:NAME:VALUE           Extra data
                                       Can be given multiple times.
                                       --hint=int32:urgency:0              (note)
                                       --hint=string:category:mail         (note)
                                       --hint=boolean:transient:false
                                       --hint=string:desktop-entry:firefox
                                       --hint=string:image-path:/path/to/file.png|jpg|svg|...

                                       TYPE is the data type, one of: boolean, int, double, byte, string

  -A, --action=[NAME=]LABEL            Return value when action button is clicked
                                       Implies --wait to wait for user input. May be set multiple times.
                                       Can't be combined with other actions running commands.
                                       LABEL is a label for a button.
                                       NAME is the value to print to stdout when the action is invoked,
                                       or the numerical index of the option if ommited (starting with 1).

  -o, --action=LABEL:COMMAND           Run command when action button is clicked
                                       Can be given multiple times. Can't be used with --wait.
                                       LABEL is a label for a button.
                                       COMMAND is a shell command to run when the LABEL button is pressed.

  -d, --default-action=COMMAND         Default action                      (note)
                                       COMMAND is run if the notification is clicked. Can't be used with --wait.

  -l, --close-action=COMMAND           Close action
                                       COMMAND is run when the notification closes (whether clicked or expired).
                                       Use in combination with -t0 (never self-expire) to get a behavior
                                       similar to default-action on servers that don't support default-action.
                                       Can't be used with --wait.

  -p, --print-id                       Prints the ID of the created notification

  -r, --replace=ID, --replace-id=ID    ID of an existing notification to update

  -R, --replace-file=FILENAME          write ID to & read ID from FILENAME

  -t, --expire-time=TIME               Time-To-Live, in milliseconds, before the notification closes itself
                                       Note that even though milliseconds are expected for TIME, any value is
                                       rounded down to full seconds. Beware of values below 1000 milliseconds,
                                       because 0 = forever.

  -f, --force-expire                   Actively close the notification after TIME,
                                       or after processing any of it's actions

  -s, --close=ID                       Close notification with ID

  -w, --wait                           Wait for the notification to be closed before exiting
                                       If --expire-time is set, it will be used as the maximum waiting time
                                       and --force-expire is implied.

  -v, --version                        Display script version

  -?, --help                           This help

  --                                   End option parsing
                                       Anything after this is treated as literal SUMMARY or BODY text,
                                       even if it looks like an option.

  SUMMARY                              Title message

  BODY                                 Message body                        (note)

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

(note) Not all servers support all features. Some options may do nothing on your server.
"
}

abrt () { echo "${SELF}: $@" >&2 ; exit 1 ; }

upd_av () {
	local v="$1"; [[ "$v" == "A" ]] || v=o
	[[ -z "$AV" ]] || [[ "$AV" == "$v" ]] || abrt "syntax: cannot mix action variants"
	AV="$v"
}

add_action () {
	local x="$1" a="$2"
	if [[ "$x" == "O" ]]; then
		if [[ "$a" =~ ^([^:=]+=)?[^:=]+$ ]]; then x=A
		elif [[ "$a" =~ ^[^:]+:[^:]+$ ]]; then x=o
		else abrt "syntax: -A / --action=\"[NAME=]LABEL\" or -o / --action=\"LABEL:COMMAND\""; fi
	else
		[[ "$x" != "A" ]] || [[ "$a" =~ ^([^:=]+=)?[^:=]+$ ]] || abrt "syntax: -A or --action=\"[NAME=]LABEL\""
		[[ "$x" != "o" ]] || [[ "$a" =~ ^[^:]+:[^:]+$ ]] || abrt "syntax: -o or --action=\"LABEL:COMMAND\""
	fi

	upd_av "$x"
	case "$x" in
		A)
			if (( AI == 0 )); then
				mkfifo -m 0600 "$AFIFO"
				trap "rm -f ${AFIFO@Q}" 0
			fi
			((++AI))

			local n l ;local -a o ;IFS='=' o=($OPTARG) ;IFS="${ifs}"
			case ${#o[@]} in
				1) n=$AI; l="${o[0]}" ;;
				2) n="${o[0]}"; l="${o[1]}" ;;
			esac

			ARGS+=( -a "$l:sh -c \"echo ${n@Q} >> ${AFIFO@Q}\"" )
			;;
		o) ARGS+=( -a "$a" ) ;;
		d) ARGS+=( -a ":$a" ) ;;
		l) ARGS+=( -a "$a" ) ;;
	esac
}

# convert all "--foo=bar" to "--foo bar"
for x in "$@"; do
	case "$x" in
		--*=*) ARGS+=("${x%%=*}" "${x#*=}") ;;
		*)     ARGS+=("$x") ;;
	esac
done

# convert all "--xoption" to "-x"
for ((i=0;i<${#ARGS[@]};i++)) {
	case "${ARGS[i]}" in
		--urgency)        ARGS[i]='-u' ;;
		--transient)      ARGS[i]='-e' ;;
		--expire-time)    ARGS[i]='-t' ;;
		--force-expire)   ARGS[i]='-f' ;;
		--app-name)       ARGS[i]='-a' ;;
		--icon)           ARGS[i]='-i' ;;
		--category)       ARGS[i]='-c' ;;
		--hint)           ARGS[i]='-h' ;;
		--action)         ARGS[i]='-O' ;;
		--default-action) ARGS[i]='-d' ;;
		--close-action)   ARGS[i]='-l' ;;
		--print-id)       ARGS[i]='-p' ;;
		--replace)        ARGS[i]='-r' ;;
		--replace-id)     ARGS[i]='-r' ;;
		--replace-file)   ARGS[i]='-R' ;;
		--close)          ARGS[i]='-s' ;;
		--wait)           ARGS[i]='-w' ;;
		--version)        ARGS[i]='-v' ;;
		--help)           ARGS[i]='-?' ;;
		--?*)             ARGS[i]='-!' ;;
		--)               break ;;
	esac
}
set -- "${ARGS[@]}"

# parse the now-normalized all-short options
ARGS=()
OPTIND=1
while getopts 'u:t:a:i:c:h:A:o:O:d:l:r:R:s:efpwv?!' x ;do
	case "$x" in
		u)
			case "$OPTARG" in
				low)      ARGS+=( -h "urgency:0" ) ;;
				normal)   ARGS+=( -h "urgency:1" ) ;;
				critical) ARGS+=( -h "urgency:2" ) ;;
				*)        abrt "invalid urgency, valid: low, normal, critical" ;;
			esac
			;;
		e) ARGS+=( -h "transient:true" ) ;;
		t) TTL=${OPTARG} ;((TTL<=0)) || ARGS+=( -t $((TTL/1000)) ) ;;
		f) ARGS+=( -f ) ;;
		a) ARGS+=( -N "$OPTARG" ) ;;
		i) ARGS+=( -n "$OPTARG" ) ;;
		c)
			typeset -a c ;IFS=, c=($OPTARG) ;IFS="${ifs}"
			for y in "${c[@]}"; do ARGS+=( -h "category:$y" ); done
			;;
		h)
			typeset -a h ;IFS=: h=($OPTARG) ;IFS="${ifs}"
			((${#h[@]}==3)) || abrt "syntax: -h or --hint=\"TYPE:NAME:VALUE\""
			[[ "${h[0]}" != "int" ]] || h[0]="int32"
			ARGS+=( -h "${h[1]}:${h[2]}:${h[0]}" )
			;;
		O|A|o|d|l) add_action "$x" "$OPTARG" ;;
		p) PRINT_ID=true ;;
		r) ARGS+=( -i "$OPTARG" ) ;;
		R) ARGS+=( -i "@$OPTARG" ) ;;
		s) ARGS+=( -c -i "$OPTARG" ) ;;
		w) upd_av "A"; WAIT=true ;;
		v) echo "${SELF} ${VERSION}" ;exit 0 ;;
		'?') help ;exit 0 ;;
		*) help ;exit 1 ;;
	esac
done
shift $((OPTIND-1))

(($#==0)) || ARGS+=( -s "$1" ) ;shift
(($#==0)) || ARGS+=( -b "$1" ) ;shift

# call notice.sh
$PRINT_ID && exec 3>&1 || exec 3>/dev/null
if $WAIT || ((AI>0)); then
	((TTL<=0)) || ARGS+=( -f )
	ARGS+=( -a "kill -USR1 $$" )

	trap "exit 0" USR1
	"$(dirname "${BASH_SOURCE[0]}")/notice.sh" "${ARGS[@]}" >&3
	if ((AI>0)); then read -r AV <"$AFIFO"; echo "$AV"
	else read -u 2; fi
else
	exec "$(dirname "${BASH_SOURCE[0]}")/notice.sh" "${ARGS[@]}" >&3
fi
