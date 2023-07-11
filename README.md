# notice.sh

Desktop notification client using only bash and gdbus.

This is [bkw777/notice.sh](https://github.com/bkw777/notice.sh)  
Originally a rewrite of [vlevit/notify-send.sh](https://github.com/vlevit/notify-send.sh)

Differences:
* Refactored to remove all the unnecessary external tools (dc, bc, sed)
* Remove unnecessary here-docs (they create temp files behind the scenes)
* Remove unnecessary subshells
* General optimizing and tightening
* Fix background process management for actions
* Remove redundant commandline options
* Combine notify-send.sh and notify-action.sh into single notice.sh

Requires `bash` and `gdbus` (part of glib2).

## Install
```
$ sudo apt install bash libglib2.0-bin
$ sudo make install
```
It's also a single self-contained script that can be run from anywhere without necessarily "installing". For example, [bkw777/mainline](https://github.com/bkw777/mainline) includes it and runs it out of a lib dir.

## Usage
```
Usage:
  ${SELF} [OPTIONS...] [--] [SUMMARY]

Options:
  -N, --app-name=APP_NAME           Formal name of the application sending the notification.
                                    ex: "Mullvad VPN"

  -n, --icon=ICON                   Icon or image to display. Forms:
                                    * basename of *.desktop file: --icon=firefox
                                    * standard themed icon name:  --icon=dialog-information
                                      https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                    * path to image file          --icon=/path/to/file.svg  (png, jpg, ...)

  -s, --summary=SUMMARY             Title message.
                                    If both this and trailing non-option args are supplied,
                                    this takes precedence and the trailing args will be ignored

  -b, --body=BODY                   Message body  (note)

  -h, --hint=NAME:VALUE[:TYPE]      Extra data. Can be given multiple times. Examples:
                                    --hint=urgency:0      (note)
                                    --hint=category:mail  (note)
                                    --hint=transient:false
                                    --hint=desktop-entry:firefox
                                    --hint=image-path:/path/to/file.png|jpg|svg|...

                                    TYPE is the data type like "string" or "boolean"
                                    and can usually be omitted.

  -a, --action=[[LABEL]:]COMMAND    Action
                                    Can be given multiple times.
                                    LABEL is a label for a button.
                                    COMMAND is a shell command to run when action is invoked.

               LABEL:COMMAND        button-action
                                    COMMAND is run if the LABEL button is pressed

               :COMMAND             default-action  (note)
                                    COMMAND is run if the notification is clicked

               COMMAND              close-action
                                    COMMAND is run when the notification closes (whether clicked or expired)
                                    Use in combination with -t0 (never self-expire) to get a behavior similar to
                                    default-action on servers that don't support default-action.

  -p, --print-id                    Print the notification ID.

  -i, --id=ID                       ID of an existing notification to update or close.
  -i, --id=@FILENAME                Read ID from & write ID to FILENAME.

  -t, --ttl=TIME                    Time-To-Live, in seconds, before the notification closes itself.
                                    0 = forever

  -f, --force-close                 Actively close the notification after TTL seconds,
                                    or after processing any of it's actions.

  -c, --close                       Close notification. (requires --id)

  -v, --version                     Display script version.

  -?, --help                        This help.

  --                                End option parsing.
                                    Anything after this is treated as literal SUMMARY text,
                                    even if it looks like an option.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

(note) Not all servers support all features. Some options may do nothing on your server.
```

There is also a `-%` option for internal use to launch the background process to watch dbus for the button presses and run the commands specified by `--action`

As a convenience, any trailing non-option arguments are taken as alternative way to supply the summary instead of `--summary`  
This allows to send simple notifications by just:  
`notice this is a message` vs `notice --summary="this is a message"` or `notice -s "this is a message"`
If both `--summary` and trailing args are supplied, `--summary` is used and the trailing args are ignored.

`--` ends option parsing, which can be used to prevent text that looks like options from being interpreted as more options.  
Example: `notice -n dialog-information --this causes an unrecognized option error--`  
while, `notice -n dialog-information -- --this does not cause an unrecognized option error--`  

All options are optional. You can actually give no options at all and it produces an empty notification.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

So, for example, to notify a user of a new email:
```
$ notice --icon=mail-unread --app-name=mail --hint=sound-name:message-new-email --summary="The Subject" --body="Some body text"
```
(not all notification servers support sounds, so you may not hear any sound)

To update or close an existing notification, you need to know its ID.  
To know the ID you have to collect it from `--print-id` when it's created.
```
$ notice --ttl=0 --print-id Initial Message
37
```

Update this notification using `--id`
```
$ notice --ttl=0 --id=37 Updated Message
```

Close this notification
```
$ notice --id=37 --close
```

`--id=@filename` automates that process
```
$ idf=/tmp/notifcation_id.$$ \
  ;notice -t0 -i @$idf Initial Message \
  ;sleep 2 \
  ;notice -t0 -i @$idf Updated Message \
  ;sleep 2 \
  ;notice -c -i @$idf
```

Example, to increase volume by 5% and show the current volume value,  
always updating the same notification rather than generating new ones
```
$ amixer sset Master 0 ;for ((i=0;i<10;i++)) {
  notice -i @/tmp/vnid -n sound -s "Sound Volume" -b "$(amixer sset Master 5%+ |awk '/[0-9]+%/ {print $2,$5}')"
  sleep 1
}
```

To add buttons to the notification, use one or more `--action`
```
$ notice -t0 -a "white xterm:xterm -bg white -fg black" -a "black xterm:xterm -bg black -fg white" action buttons
```

To set the "default-action", use `--action=":command ..."`  
Action is invoked if the user clicks on the notification but not on any button.
Not all servers support "default-action", so this option may do nothing.

To set the "close-action", use `--action="command ..."`  
Action is invoked when the notification closes, if not already closed by some other action.
Similar to default-action, in that if the user clicks on a notification, that closes it,
and so would trigger the close-action. But close-action is also invoked if the notification
closes itself from timimg out, and is not invoked if the notification closes as part of
some other button-action or default-action.
Use with `-t0` to get a behavior similar default-action when the notification server doesn't support default actions.  

```
$ notice \
  -n dialog-information \
  -t 5 \
  -a "Button 0:notice Button 0 invoked" \
  -a "Button 1:notice Button 1 invoked" \
  -a ":notice default-action invoked" \
  -a "notice close-action invoked" \
  -s "Actions Test" \
  -b "message body text"
```
