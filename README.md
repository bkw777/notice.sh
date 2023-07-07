# notice.sh

Desktop notification client using only bash and gdbus.

This is [bkw777/notice.sh](https://github.com/bkw777/notice.sh),  
originally a rewrite of [vlevit/notify-send.sh](https://github.com/vlevit/notify-send.sh)

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

## Usage
```
notice [OPTION...] [TITLE] [BODY]

Options:
-N, --app-name=APP_NAME           Specify the formal name of application sending the notification.
                                  ex: "Mullvad VPN"

-n, --icon=ICON                   Specify an image or icon to display.
                                  * installed *.desktop name   ex: "firefox"
                                  * standard themed icon name  ex: "dialog-information"
                                    https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html
                                  * path to an image file

-T, --title=TITLE                 Title of notification

-B, --body=BODY                   Message body
                                  If both this and trailing non-option args are supplied,
                                  this takes precedence and the trailing args are ignored

-a, --action=[LABEL:]COMMAND      Specify an action button. Can be given multiple times.
                                  LABEL is the label for the button.
                                  COMMAND is a shell command to run when LABEL button is pressed.
                                  If LABEL: is absent, COMMAND is run when the notification is dismissed.

-h, --hint=NAME:VALUE[:TYPE]      Specify extra data. Can be given multiple times. Examples:
                                  --hint=urgency:0
                                  --hint=category:device.added
                                  --hint=transient:false
                                  --hint=desktop-entry:firefox
                                  --hint=image-path:/path/to/file.png|jpg|svg|...

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

There is also a `-%` option which is used internally to launch the background process to watch dbus for the button presses and run the commands specified by --action

As a convenience, any trailing non-option arguments are taken as another way to supply the message body instead of --body  
This allows to send simple notifications by just:  
`notice this is a message` vs `notice --body="this is a message"` or `notice -B "this is a message"`
If both --body and trailing args are supplied, --body is used and the trailing args are ignored.

`--` ends option parsing, which can be used to prevent text that looks like options from being interpreted as more options.  
Example: `notice -n dialog-information -- --foo --bar -a -b these are not options`  
will produce a notification with the message body text `--foo --bar -a -b these are not options`

Reference: https://specifications.freedesktop.org/notification-spec/notification-spec-latest.html

So, for example, to notify a user of a new email:
```
$ notice --icon-name=mail-unread --app-name=mail --hint=sound-name:message-new-email --title=Subject --body=Message
```

To replace or close an existing message first we need to know its id.
To know the id we have to run `notice` with `--print-id` the first time:
```
$ notice -t 0 --print-id Initial Message
37
```

Update this notification using the `--id` option:
```
$ notice -t 0 --id=37 Updated Message
```

Close this notification:
```
$ notice --id=37 --dismiss
```

Use `--id=@filename` to both store & retrieve the ID from a file to keep updating a single notification  
For example, to increase volume by 5% and show the current volume value:
```
$ notice --id=@/tmp/volumenotification --icon=sound --title="Audio Volume" $(amixer sset Master 5%+ |awk '/[0-9]+%/ {print $2,$5}')
```
Then press up-arrow and Enter to repeat the same command a few times in a row,
and note that a single notification updates rather than adding more notifications.

To add one or more buttons to the notification, use one or more `--action=...`:
```
$ notice --action="Show another notification:notice New Message" Initial Message
```

To perform an action when the notification is closed, use `--action=...` with no `LABEL:`
```
$ notice \
  -n dialog-information \
  -t 0 \
  -a "Button 1:notice 'Button 1 was pressed'" \
  -a "Button 2:notice 'Button 2 was pressed'" \
  -a "Button 3:notice 'Button 3 was pressed'" \
  -a "notice 'Notification was closed'" \
  -T "Actions Test Title" \
  -B "Actions Test Message"
```

To perform a "default action", when the notification is clicked but not on any button, use `--action=...` with `"":` or `'':` for `LABEL:`  
This is very similar to the close action above, because clicking on a notification generally dismisses it.  
```
$ notice -a "'':notice 'default action was invoked'" -T "test default action" "message body"
```
Not all notification daemons support the "default action", so for example on XFCE this just creates a button with a "" label.  
In that case, you can usually just use the close action (`--action=...` with no `LABEL:` not even the colon) combined with `-t 0` to get almost the same effect.
It's not exactly the same, because the close action is also invoked if the notification closes by itself from normal timeout expiration, while default-action is only invoked if the user clicks on the notification. This is why you probably want to use `-t 0` with close-action, to prevent the notification from closing except by clicking it.

