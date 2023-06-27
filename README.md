This is [bkw777/notify-send.sh](https://github.com/bkw777/notify-send.sh)
a rewrite of [vlevit/notify-send.sh](https://github.com/vlevit/notify-send.sh)
The main purpose and differences are:
* Refactored to remove all the unnecessary external tools (dc, bc, sed)
* Remove unnecessary here-docs (they create temp files behind the scenes)
* Remove unecessary subshells
* General optimizing and tightening
* Fix the handling of actions. For a lengthy explaination of the problem and the fix, see [bkw777/mainline/blob/master/lib/notify_send/mainline_changes.txt](https://raw.githubusercontent.com/bkw777/mainline/master/lib/notify_send/mainline_changes.txt)
* Also a lot of admittedly gratuitous stylistic changes because I just prefer short variable names except where actually useful, and I just prefer "foo && { stuff }" vs "if foo ;then stuff ;fi"  etc.

# notify-send.sh

notify-send.sh is a replacement for notify-send (from libnotify) with ability to update and close existing notifications, and specify commands to be run in response to actions.

Requires `bash` and `gdbus` (part of glib2).

## Install
```
$ sudo apt install bash libglib2.0-bin
$ sudo make install
```

## Usage
    notify-send.sh [OPTION...] <SUMMARY> [BODY]

    Application Options:
      -u, --urgency=LEVEL               Specifies the urgency level (low, normal, critical).
      -t, --expire-time=TIME            Specifies the timeout in milliseconds at which to expire the notification.
      -f, --force-expire                Actively close the notification after the expire time, or after processing any action.
      -a, --app-name=APP_NAME           Specifies the app name for the icon
      -i, --icon=ICON[,ICON...]         Specifies an icon filename or stock icon to display.
      -c, --category=TYPE[,TYPE...]     Specifies the notification category.
      -h, --hint=TYPE:NAME:VALUE        Specifies basic extra data to pass. Valid types are int, double, string and byte.
      -o, --action=LABEL:COMMAND        Specifies an action. Can be passed multiple times. LABEL is usually a button's label. COMMAND is a shell command executed when action is invoked.
      -l, --close-action=COMMAND        Specifies the action invoked when the notification is closed.
      -p, --print-id                    Print the notification ID to the standard output.
      -r, --replace=ID                  Replace existing notification.
      -R, --replace-file=FILE           Store and load notification replace ID to/from this file.
      -s, --close=ID                    Close notification.
      -v, --version                     Version of the package.
      -?, --help                        This help

So, for example, to notify a user of a new email:
```
$ notify-send.sh --icon=mail-unread --app-name=mail --hint=sound-name:message-new-email Subject Message
```

To replace or close an existing message first we need to know its id.
To know the id we have to run notify-send.sh with `--print-id` the first time:
```
$ notify-send.sh --print-id "The Subject" "The Message"
37
```

Update this notification using `--replace` option:
```
$ notify-send.sh --replace=37 "New Subject" "New Message"
```

Close this notification:
```
$ notify-send.sh --close=37
```

Use `--replace-file` to make sure that no more than one notification is created per file.  
`--replace-file` means to get the ID from the given filename, and to store the ID in that filename.  
For example, to increase volume by 5% and show the current volume value:
```
$ notify-send.sh --replace-file=/tmp/volumenotification "Increase Volume" "$(amixer sset Master 5%+ | awk '/[0-9]+%/ {print $2,$5}')"
```

To add one or more buttons to the notification, use one or more `--action=...`:
```
$ notify-send.sh "Subject" "Message" --action "Show another notification:notify-send.sh 'New Subject' 'New Message'"
```

To perform an action when the notification is closed, use `--close-action=...`

    $ notify-send.sh "Subject" "Message" \
        -o "Button0 Action:notify-send.sh 'Button0 Action'" \
        -o "Button1 Action:notify-send.sh 'Button1 Action'" \
        -o "Button2 Action:notify-send.sh 'Button2 Action'" \
        -l "notify-send.sh 'Close Action'"
