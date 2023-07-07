# notify-send.sh

Replacement for notify-send (from libnotify) with ability to update and close existing notifications, and specify commands to be run in response to actions.

This is [bkw777/notify-send.sh.sh](https://github.com/bkw777/notify-send.sh),  
a rewrite of [vlevit/notify-send.sh](https://github.com/vlevit/notify-send.sh)  

Differences:
* Refactored to remove all the unnecessary external tools (dc, bc, sed)
* Remove unnecessary here-docs (they create temp files behind the scenes)
* Remove unnecessary subshells
* General optimizing and tightening
* Fix background process management for actions
* Remove redundant commandline options

Requires `bash` and `gdbus` (part of glib2).

## Install
```
$ sudo apt install bash libglib2.0-bin
$ sudo make install
```

## Usage
```
notify-send.sh [OPTION...] [TITLE] [BODY]

Options:
-N, --app-name=APP_NAME           Specify the formal name of application sending the notification.
                                  ex: "Mullvad VPN"

-n, --icon=ICON                   Specify an image or icon to display.
                                  * installed *.desktop name   ex: "firefox"
                                  * standard themed icon name  ex: "dialog-information"
                                    https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                  * path to an image file

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
```

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

So, for example, to notify a user of a new email
```
$ notify-send.sh --icon-name=mail-unread --app-name=mail --hint=sound-name:message-new-email Subject Message
```

To replace or close an existing message first we need to know its id.
To know the id we have to run `notify-send.sh` with `--print-id` the first time
```
$ notify-send.sh --print-id "The Subject" "The Message"
37
```

Update this notification using the `--id` option
```
$ notify-send.sh --id=37 "New Subject" "New Message"
```

Close this notification
```
$ notify-send.sh --id=37 --dismiss
```

Use `--id=@filename` to both store & retrieve the ID from a file to keep updating a single notification  
For example, to increase volume by 5% and show the current volume value
```
$ notify-send.sh --id=@/tmp/volumenotification "Increase Volume" "$(amixer sset Master 5%+ | awk '/[0-9]+%/ {print $2,$5}')"
```

To add one or more buttons to the notification, use one or more `--action=...`
```
$ notify-send.sh --action="Show another notification:notify-send.sh 'New Title' 'New Message'" "Initial Title" "Initial Message"
```

To perform an action when the notification is closed, use `--action=...` with no `LABEL:`
```
$ notify-send.sh \
  -a "Button 1:notify-send.sh 'Button 1 was pressed'" \
  -a "Button 2:notify-send.sh 'Button 2 was pressed'" \
  -a "Button 3:notify-send.sh 'Button 3 was pressed'" \
  -a "notify-send.sh 'Notification was closed'" \
  "Actions Test Title" \
  "Actions Test Message"
```

To perform a "default action", when the notification is clicked but not on any button, use `--action=...` with `"":` or `'':` or `:` for `LABEL:`  
This is very similar to the close action above, because clicking on a notification generally dismisses it.  
Not all notification daemons support the "default action", so for example on XFCE this just creates a button with a "" label.  
In that case, you can usually just use the close action to get the same effect.
```
$ notify-send.sh -a "'':notify-send.sh 'default action was invoked'" "test default action" "message body"
```
