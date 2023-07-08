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
notice [OPTION...] [BODY]

Options:
-N, --app-name=APP_NAME           Formal name of application sending the notification.
                                  ex: "Mullvad VPN"

-n, --icon=ICON                   Image or icon to display. May be be specified a few different ways:
                                  * installed *.desktop name   ex: "firefox"
                                  * standard themed icon name  ex: "dialog-information"
                                    https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                  * path to an image file

-T, --title=TITLE                 Title or summary

-B, --body=BODY                   Message body
                                  If both this and trailing non-option args are supplied,
                                  this takes precedence and the trailing args are ignored

-a, --action=[LABEL:]COMMAND      Define an action to perform in response to clicking a button,
                                  or clicking the notification itself, or when the notification is closed.
                                  LABEL is the label for a button.
                                  COMMAND is a shell command to run when the action is invoked.
                                  Can be given multiple times to define multiple buttons, close, and default actions.

                                  If LABEL: is not empty, produces a button with LABEL on it,
                                    and COMMAND is run if the user clicks that button.

                                  If LABEL: is "": , action is the "default-action".
                                    If the notification server supports "default-action", then COMMAND
                                    is run when the user clicks on the notification but not on any button,
                                    otherwise this just produces a button with a "" label.

                                  If LABEL: is absent (no text or colon), action is the "close-action".
                                    COMMAND is run when the notification closes,
                                    whether from clicking on it to dismiss it or by timing out.
                                    Use in combination with -t 0 (never time out) to get an effect
                                    similar to "default-action" on notification servers that do not
                                    support "default-action".

-h, --hint=NAME:VALUE[:TYPE]      Specify extra data. Can be given multiple times.
                                  See the link to the notifications spec below. Examples:
                                  --hint=urgency:0
                                  --hint=category:device.added
                                  --hint=transient:false
                                  --hint=desktop-entry:firefox
                                  --hint=image-path:/path/to/file.png

                                  :TYPE may usually be omitted.
                                  TYPE is the data type for VALUE, from a list of specific types from the notification spec
                                  example: --hint=urgency:0 is equivalent to --hint=urgency:0:byte

-p, --print-id                    Print the notification ID.

-i, --id=<ID|@FILENAME>           ID, or file containing an ID, of an existing notification to update or dismiss.
                                  ID is an integer, generated by the notification server for each new notification.

                                  If "@FILENAME", and the file doesn't exist or is empty,
                                  then a new notification is created and it's ID is written to the file.

                                  @FILENAME basically automates collecting the ID from --print-id
                                  and then using it with --id later.

-t, --expire-time=TIME            Time in seconds for the notification to live.
                                  0 = never expire

-f, --force-expire                Actively close the notification after the expire time,
                                  or after processing any of it's actions (see --action).

-d, --dismiss                     Close notification. (requires --id)

-v, --version                     Display script version.

-?, --help                        This help.
```

There is also a `-%` option which is used internally to launch the background process to watch dbus for the button presses and run the commands specified by `--action`

As a convenience, any trailing non-option arguments are taken as alternative way to supply the message body instead of `--body`  
This allows to send simple notifications by just:  
`notice this is a message` vs `notice --body="this is a message"` or `notice -B "this is a message"`
If both `--body` and trailing args are supplied, `--body` is used and the trailing args are ignored.

`--` ends option parsing, which can be used to prevent text that looks like options from being interpreted as more options.  
Example: `notice -n dialog-information -- --version -N these are not options`  
will produce a notification with message body text `--version -N these are not options`

All options are optional. You can actually give no options at all and it produces an empty notification.

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

So, for example, to notify a user of a new email:
```
$ notice --icon=mail-unread --app-name=mail --hint=sound-name:message-new-email --title="The Subject" --body="Some body text"
```
(not all notification servers support sounds, so you may not hear any sound)

To update or close an existing notification, you need to know its ID.  
To know the ID you have to collect it from `--print-id` when it's created.
```
$ notice -t 0 --print-id Initial Message
37
```

Update this notification using `--id`
```
$ notice -t 0 --id=37 Updated Message
```

Close this notification
```
$ notice --id=37 --dismiss
```

`--id=@filename` automates that process
```
$ notice -t 0 -i @/tmp/nid Initial Message
$ sleep 2
$ notice -t 0 -i @/tmp/nid Updated Message
$ sleep 2
$ notice -d -i @/tmp/nid
```

Example, to increase volume by 5% and show the current volume value
```
$ notice -i @/tmp/volumenotification -n sound -T "Audio Volume" $(amixer sset Master 5%+ |awk '/[0-9]+%/ {print $2,$5}')
```
Repeat the same command a few times in a row, and see that a single notification updates rather than adding more notifications.

To add one or more buttons to the notification, use one or more `--action`
```
$ notice -t 0 -a "white xterm:xterm -bg white -fg black" -a "black xterm:xterm -bg black -fg white" action buttons
```

To set the "close-action", an action that is invoked when the notification is closed, use `--action=command...` with no `label:`  
Use with `-t 0` to get the same effect as a "default-action" when the notification server doesn't support default actions.  
The command is invoked if the user clicks on the notification itself. If you don't use `-t 0` the the command will also run when the notification closes itself from timing out, which would usually be undesireable.
```
$ notice \
  -n dialog-information \
  -t 0 \
  -a "Button:notice Button was pressed" \
  -a "notice Notification was clicked" \
  -T "Actions Test" \
  -B "message body text"
```

To set the "default-action", an action that is invoked when the notification is clicked but not on any button, use `--action='':command...`  ('' or "")
This is similar to "close-action", except the command is only run if the user clicks on the notification, not if the notification closes itself from timing out.
```
$ notice -a "'':notice default action was invoked" -T "test default action" message body text
```
Not all notification servers support "default-action", so for example on XFCE this just creates a normal action button with a '' label.  
