# IRC Relay

![Minimum UT2004 Version](https://img.shields.io/badge/UT2004-v3369+-blue.svg)
[![License](https://img.shields.io/github/license/d03n3rfr1tz3/ut2004-ircRelay.svg)](LICENSE)

This mutator is a clone of the IRC Relay plugin for BZFlag I (partially) made.
It relays the chat between an Unreal Tournament 2004 server and an IRC channel.
It runs only on the server, so clients do not need to download anything.

## Requirements

You need an Unreal Tournament 2004 dedicated server with patch 3369 or newer, e.g. the patch 3374 from OldUnreal: \
https://github.com/OldUnreal/UT2004Patches

## Usage

### Compiling the mutator

Clone this repository into a folder named `ircRelay` in your UT2004 folder, so the classes end up in `ircRelay/Classes`.
Add `EditPackages=ircRelay` after the other `EditPackages` lines in the `[Editor.EditorEngine]` section of your server ini
and run `ucc make` in the `System` folder. This creates the `System/ircRelay.u` package.

### Loading the mutator

Drop the `ircRelay.ini` in your `System` folder and start the server with the mutator, e.g.

```
ucc server DM-Rankin?game=XGame.xDeathMatch?mutator=ircRelay.MutIrcRelay
```

Do not add the package to the `ServerPackages`, the clients do not need it.

### Configuration

The configuration is in the `ircRelay.ini` file. Just fill out the values and you are ready.
The value for `debug` can be between 0 and 4, depending on how much information you want in the server log.

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `ircAddress` | string |  | Required. The address of your IRC server. |
| `ircPort` | int | 6667 | Required. The port of your IRC server. |
| `ircChannel` | string |  | Required. The channel your IRC Relay should join, without the `#`. |
| `ircNick` | string |  | Required. The nickname your IRC Relay should use. |
| `ircPass` | string |  | Optional. The password for the IRC server. |
| `ircAuthType` | string |  | Optional. The authentication type of the IRC server. Choose one: `AuthServ`, `NickServ` or `Q`. |
| `ircAuthPass` | string |  | Optional. The authentication password for the IRC server. |
| `ircIgnore` | string |  | Optional. Ignored IRC users, one `ircIgnore=` line per user. Messages from these users will not be passed into the UT2004 chat. |
| `ircPrefix` | string |  | Optional. Prefix for all messages sent into the IRC channel, e.g. `[UT2004]-`. |

### Map changes

A map change ends the connection to the IRC server, so the IRC Relay quits and joins the channel again on every map.
Players who were on the server before the map change are not announced again when they come back within 90 seconds.

### Messages for a specific game

If you run several game servers with an IRC Relay in the same channel, an IRC message can be sent to only one of them
by starting it with the tag of that game in brackets, followed by a space, e.g. `[UT2004] Hello`.
The tag is taken from the brackets at the start of `ircPrefix`. A message with the own tag is passed into the UT2004 chat
without the tag, a message with any other tag is not passed at all. Messages without a tag are passed as usual.

## License

[LICENSE](LICENSE)
