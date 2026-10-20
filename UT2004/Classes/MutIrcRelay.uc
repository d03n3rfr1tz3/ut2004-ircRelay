//=============================================================================
// MutIrcRelay
// Relays the chat between a UT2004 server and an IRC channel.
// Runs only on the server, clients do not need to download anything.
//=============================================================================
class MutIrcRelay extends Mutator
	config(ircRelay);

var config int debug;
var config string ircAddress;
var config int ircPort;
var config string ircChannel;
var config string ircNick;
var config string ircPass;
var config string ircAuthType;
var config string ircAuthPass;
var config array<string> ircIgnore;
var config string ircPrefix;

struct PlayerEntry
{
	var int PlayerID;
	var string Nick;
	var string Address;
};

var IrcLink Link;
var IrcBroadcastHandler Handler;
var array<string> SendQueue;
var array<PlayerEntry> Players;
var array<string> TravelPlayers;
var float ReconnectTime;
var float NextSendTime;
var float TravelEndTime;
var int RetryCount;
var int PingCount;
var bool bEnabled;
var bool bTraveling;

const MaxQueue = 50;
const TravelTime = 90.0;
const ConnectTimeout = 30.0;
const IdleTimeout = 300.0;

event PostBeginPlay()
{
	Super.PostBeginPlay();

	Handler = Spawn(class'IrcBroadcastHandler');
	Handler.Relay = self;
	Level.Game.BroadcastHandler.RegisterBroadcastHandler(Handler);

	// players of the previous map reconnect after a map change and should not be announced again
	TravelPlayers = class'IrcRelayState'.default.Players;
	TravelEndTime = Level.TimeSeconds + TravelTime;
	class'IrcRelayState'.default.Players.Length = 0;
	class'IrcRelayState'.static.StaticSaveConfig();

	if (ircAddress == "" || ircPort == 0 || ircChannel == "" || ircNick == "")
		DebugLog("IRC relay is not configured, check ircAddress, ircPort, ircChannel and ircNick in ircRelay.ini", 1);
	else
		bEnabled = true;

	SetTimer(0.25, true);
}

event Timer()
{
	CheckPlayers();
	CheckLink();
	FlushQueue(false);
}

//=============================================================================
// Players
//=============================================================================

function CheckPlayers()
{
	local int i, j;
	local PlayerReplicationInfo PRI;
	local PlayerController PC;
	local PlayerEntry Entry;
	local string Nick;

	if (Level.GRI == None)
		return;

	for (i = 0; i < Level.GRI.PRIArray.Length; i++)
	{
		PRI = Level.GRI.PRIArray[i];
		if (PRI == None || PRI.bBot)
			continue;
		PC = PlayerController(PRI.Owner);
		if (PC == None || NetConnection(PC.Player) == None)
			continue;

		Nick = PlayerName(PRI);
		j = FindPlayer(PRI.PlayerID);
		if (j >= 0)
		{
			if (Players[j].Nick != Nick)
			{
				Queue(PlayerColor(PRI) $ Players[j].Nick $ Chr(15) $ " renamed to " $ PlayerColor(PRI) $ Nick);
				Players[j].Nick = Nick;
			}
			continue;
		}

		Entry.PlayerID = PRI.PlayerID;
		Entry.Nick = Nick;
		Entry.Address = PlayerAddress(PC);
		Players[Players.Length] = Entry;

		if (IsTravelPlayer(Entry.Address))
			continue;
		if (PRI.bOnlySpectator)
			Queue(PlayerColor(PRI) $ Nick $ Chr(15) $ " joined as spectator from " $ Entry.Address);
		else
			Queue(PlayerColor(PRI) $ Nick $ Chr(15) $ " joined the game from " $ Entry.Address);
	}

	// players of the previous map who did not come back
	if (TravelPlayers.Length > 0 && Level.TimeSeconds >= TravelEndTime)
	{
		for (i = 0; i < TravelPlayers.Length; i++)
		{
			j = InStr(TravelPlayers[i], " ");
			if (j > 0)
				Queue(Chr(15) $ Mid(TravelPlayers[i], j + 1) $ Chr(15) $ " left the game");
		}
		TravelPlayers.Length = 0;
	}
}

function NotifyLogout(Controller Exiting)
{
	local int i;

	if (Exiting != None && Exiting.PlayerReplicationInfo != None)
	{
		i = FindPlayer(Exiting.PlayerReplicationInfo.PlayerID);
		if (i >= 0)
		{
			if (!bTraveling)
				Queue(PlayerColor(Exiting.PlayerReplicationInfo) $ Players[i].Nick $ Chr(15) $ " left the game");
			Players.Remove(i, 1);
		}
	}

	Super.NotifyLogout(Exiting);
}

function ServerTraveling(string URL, bool bItems)
{
	local int i;

	bTraveling = true;

	// remember the players, so they are not announced again after the map change
	class'IrcRelayState'.default.Players.Length = Players.Length;
	for (i = 0; i < Players.Length; i++)
		class'IrcRelayState'.default.Players[i] = Players[i].Address $ " " $ Players[i].Nick;
	class'IrcRelayState'.static.StaticSaveConfig();

	// the connection does not survive the map change, so send everything that is left
	FlushQueue(true);
	if (Link != None && Link.bOpened)
		Link.SendLine("QUIT :Map change");

	Super.ServerTraveling(URL, bItems);
}

function bool IsTravelPlayer(string Address)
{
	local int i;

	for (i = 0; i < TravelPlayers.Length; i++)
	{
		if (Left(TravelPlayers[i], Len(Address) + 1) == (Address $ " "))
		{
			TravelPlayers.Remove(i, 1);
			return true;
		}
	}
	return false;
}

function int FindPlayer(int PlayerID)
{
	local int i;

	for (i = 0; i < Players.Length; i++)
		if (Players[i].PlayerID == PlayerID)
			return i;
	return -1;
}

function string PlayerName(PlayerReplicationInfo PRI)
{
	return Level.Game.StripColor(PRI.PlayerName);
}

function string PlayerAddress(PlayerController PC)
{
	local string Address;
	local int i;

	Address = PC.GetPlayerNetworkAddress();
	i = InStr(Address, ":");
	if (i > 0)
		Address = Left(Address, i);
	return Address;
}

function string PlayerColor(PlayerReplicationInfo PRI)
{
	if (PRI.bOnlySpectator)
		return Chr(3) $ "14";
	if (PRI.Team != None && PRI.Team.TeamIndex == 0)
		return Chr(3) $ "04";
	if (PRI.Team != None && PRI.Team.TeamIndex == 1)
		return Chr(3) $ "02";
	return Chr(15);
}

//=============================================================================
// Game to IRC
//=============================================================================

function GameChat(PlayerReplicationInfo PRI, string Message, bool bTeam)
{
	local string Nick;

	if (PRI.bBot)
		return;

	Nick = PlayerName(PRI);
	if (bTeam)
		Nick = Nick $ " (team)";
	Message = Level.Game.StripColor(Message);

	if (Left(Message, 4) ~= "/me ")
		QueueRaw(Chr(1) $ "ACTION " $ ircPrefix $ PlayerColor(PRI) $ Nick $ " " $ Mid(Message, 4) $ Chr(1));
	else
		Queue(PlayerColor(PRI) $ Nick $ ": " $ Chr(15) $ Message);
}

function Queue(string Message)
{
	QueueRaw(ircPrefix $ Message);
}

function QueueRaw(string Message)
{
	if (!bEnabled)
		return;
	if (SendQueue.Length >= MaxQueue)
		SendQueue.Remove(0, 1);
	SendQueue[SendQueue.Length] = Message;
}

function FlushQueue(bool bAll)
{
	while (SendQueue.Length > 0 && Link != None && Link.bJoined && (bAll || Level.TimeSeconds >= NextSendTime))
	{
		Link.SendLine("PRIVMSG #" $ ircChannel $ " :" $ SendQueue[0]);
		SendQueue.Remove(0, 1);
		NextSendTime = Level.TimeSeconds + 1.0;
		if (!bAll)
			break;
	}
}

//=============================================================================
// IRC to game
//=============================================================================

function IrcChat(string Nick, string Message)
{
	local int i;
	local string White, Yellow;

	for (i = 0; i < ircIgnore.Length; i++)
	{
		if (ircIgnore[i] ~= Nick)
		{
			DebugLog("Message from " $ Nick $ " got ignored", 4);
			return;
		}
	}

	if (!Filter(Message))
	{
		DebugLog("Message from " $ Nick $ " got filtered", 4);
		return;
	}

	White = Chr(27) $ Chr(255) $ Chr(255) $ Chr(255);
	Yellow = Chr(27) $ Chr(255) $ Chr(255) $ Chr(127);

	if (Left(Message, 8) == (Chr(1) $ "ACTION "))
	{
		Message = Mid(Message, 8);
		if (Right(Message, 1) == Chr(1))
			Message = Left(Message, Len(Message) - 1);
		GameMessage("* " $ White $ StripIrc(Nick) $ " " $ Yellow $ StripIrc(Message) $ " *");
	}
	else
		GameMessage(White $ StripIrc(Nick) $ ": " $ Yellow $ StripIrc(Message));
}

// messages tagged with a game, e.g. "[UT2004] text", only go into this game
function bool Filter(out string Message)
{
	local string Tag, OwnTag;
	local int i;

	if (Left(Message, 1) != "[")
		return true;
	i = InStr(Message, "] ");
	if (i < 2 || InStr(Left(Message, i), " ") >= 0)
		return true;
	Tag = Mid(Message, 1, i - 1);

	if (Left(ircPrefix, 1) == "[" && InStr(ircPrefix, "]") > 1)
		OwnTag = Mid(ircPrefix, 1, InStr(ircPrefix, "]") - 1);
	if (Tag != OwnTag)
		return false;

	Message = Mid(Message, i + 2);
	return true;
}

function GameMessage(string Message)
{
	local Controller C;
	local PlayerController PC;

	DebugLog(Message, 4);
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None)
			PC.TeamMessage(None, Message, 'Event');
	}
}

// removes IRC formatting and control characters, they would show up as boxes in the game
function string StripIrc(string Text)
{
	local string Result, Ch;
	local int i, c, Digits;

	for (i = 0; i < Len(Text); i++)
	{
		Ch = Mid(Text, i, 1);
		c = Asc(Ch);
		if (c == 3)
		{
			for (Digits = 0; Digits < 2 && i + 1 < Len(Text) && IsDigit(Mid(Text, i + 1, 1)); Digits++)
				i++;
			if (Digits > 0 && i + 2 < Len(Text) && Mid(Text, i + 1, 1) == "," && IsDigit(Mid(Text, i + 2, 1)))
			{
				i += 2;
				if (i + 1 < Len(Text) && IsDigit(Mid(Text, i + 1, 1)))
					i++;
			}
		}
		else if (c >= 32)
			Result = Result $ Ch;
	}
	return Result;
}

function bool IsDigit(string Ch)
{
	return Ch >= "0" && Ch <= "9";
}

//=============================================================================
// Connection
//=============================================================================

function CheckLink()
{
	if (Link != None)
	{
		if (Link.bFailed)
		{
			DropLink();
			ScheduleReconnect();
		}
		else if (!Link.bOpened && Level.TimeSeconds - Link.StartTime > ConnectTimeout)
		{
			DebugLog("Connection to irc server " $ ircAddress $ " timed out", 1);
			DropLink();
			ScheduleReconnect();
		}
		else if (Link.bOpened && Level.TimeSeconds - Link.LastReceive > IdleTimeout)
		{
			DebugLog("Connection to irc server " $ ircAddress $ " got no data for " $ int(IdleTimeout) $ " seconds", 1);
			DropLink();
			ScheduleReconnect();
		}
		return;
	}

	if (bEnabled && !bTraveling && Level.TimeSeconds >= ReconnectTime)
	{
		Link = Spawn(class'IrcLink');
		Link.Relay = self;
		Link.Connect();
	}
}

function DropLink()
{
	if (Link.IsConnected())
		Link.Close();
	Link.Relay = None;
	Link.Destroy();
	Link = None;
}

// wait longer with every attempt, start over once a connection was stable
function ScheduleReconnect()
{
	local int i;
	local float Delay;

	if (PingCount > 5)
	{
		PingCount = 0;
		RetryCount = 0;
	}

	Delay = 5;
	for (i = 0; i < RetryCount; i++)
		Delay *= 2;
	if (RetryCount < 6)
		RetryCount++;

	DebugLog("Reconnecting to irc server " $ ircAddress $ " in " $ int(Delay) $ " seconds", 1);
	ReconnectTime = Level.TimeSeconds + Delay;
}

function DebugLog(string Message, int DebugLevel)
{
	if (debug >= DebugLevel)
		Log(Message, 'ircRelay');
}

defaultproperties
{
	FriendlyName="IRC Relay"
	Description="Relays the chat between the server and an IRC channel."
	GroupName="IRC"
	ircPort=6667
}
