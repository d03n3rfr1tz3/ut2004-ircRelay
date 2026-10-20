# IRC Relay

![Minimum UT99 Version](https://img.shields.io/badge/UT99-v469+-blue.svg)
![Minimum UT2004 Version](https://img.shields.io/badge/UT2004-v3369+-blue.svg)
[![License](https://img.shields.io/github/license/d03n3rfr1tz3/unreal-ircRelay.svg)](LICENSE)

This mutator is a clone of the IRC Relay plugin for BZFlag I (partially) made.
It relays the chat between an Unreal Tournament server and an IRC channel.
It runs only on the server, so clients do not need to download anything.

There is one version for each game, both build the package `ircRelay`:

| Folder | Game |
| ------ | ---- |
| `UT99` | Unreal Tournament (UT99) |
| `UT2004` | Unreal Tournament 2004 |

## Requirements

- UT99: a dedicated server with patch 469 from OldUnreal: \
  https://github.com/OldUnreal/UnrealTournamentPatches \
  Clients can connect with any version from 432 on.
- UT2004: a dedicated server with patch 3369 or newer, e.g. the patch 3374 from OldUnreal: \
  https://github.com/OldUnreal/UT2004Patches

## Usage

### Compiling the mutator

Copy the folder of your game into your game folder and name it `ircRelay`, so the classes end up in `ircRelay/Classes`.
Add `EditPackages=ircRelay` after the other `EditPackages` lines in the `[Editor.EditorEngine]` section of your server ini
and run `ucc make` in the `System` folder. This creates the `System/ircRelay.u` package.

### Loading the mutator

Drop the `ircRelay.ini` of your game in your `System` folder and start the server with the mutator, e.g.

```
ucc server DM-Deck16][?game=Botpack.DeathMatchPlus?mutator=ircRelay.MutIrcRelay
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
| `ircIgnore` | string |  | Optional. Ignored IRC users. Messages from these users will not be passed into the game chat. |
| `ircPrefix` | string |  | Optional. Prefix for all messages sent into the IRC channel, e.g. `[UT99]-` or `[UT2004]-`. |

The ignore list is written differently in each game:

- UT99: up to 16 numbered lines `ircIgnore[0]=`, `ircIgnore[1]=` and so on.
- UT2004: one `ircIgnore=` line per user.

### Map changes

A map change ends the connection to the IRC server, so the IRC Relay quits and joins the channel again on every map.
Players who were on the server before the map change are not announced again when they come back within 90 seconds.

### Messages for a specific game

If you run several game servers with an IRC Relay in the same channel, an IRC message can be sent to only one of them
by starting it with the tag of that game in brackets, followed by a space, e.g. `[UT99] Hello`.
The tag is taken from the brackets at the start of `ircPrefix`. A message with the own tag is passed into the game chat
without the tag, a message with any other tag is not passed at all. Messages without a tag are passed as usual.

### Differences in UT99

- Team colors in the IRC channel cover all four teams (red, blue, green, gold).
- IRC formatting is removed in the game, and characters the UT99 fonts do not know are shown as `?`.

## License

[LICENSE](LICENSE)
