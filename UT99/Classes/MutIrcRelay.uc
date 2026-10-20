//=============================================================================
// MutIrcRelay
// Relays the chat between a UT99 server and an IRC channel.
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
var config string ircIgnore[16];
var config string ircPrefix;

struct PlayerEntry
{
	var int PlayerID;
	var string Nick;
	var string Address;
	var bool bSeen;
};

var IrcLink Link;
var string SendQueue[50];
var int QueueCount;
var PlayerEntry Players[32];
var int PlayerCount;
var string TravelPlayers[32];
var int TravelCount;
var float ReconnectTime;
var float NextSendTime;
var float TravelEndTime;
var int RetryCount;
var int PingCount;
var bool bInitialized;
var bool bEnabled;
var bool bTraveling;

var PlayerReplicationInfo LastPRI;
var string LastMsg;
var name LastType;
var float LastTime;

const TravelTime = 90.0;
const ConnectTimeout = 30.0;
const IdleTimeout = 300.0;

event PostBeginPlay()
{
	local int i;

	if (bInitialized)
		return;
	bInitialized = true;

	Level.Game.RegisterMessageMutator(self);

	// players of the previous map reconnect after a map change and should not be announced again
	for (i = 0; i < ArrayCount(TravelPlayers); i++)
	{
		if (class'IrcRelayState'.default.Players[i] != "")
			TravelPlayers[TravelCount++] = class'IrcRelayState'.default.Players[i];
		class'IrcRelayState'.default.Players[i] = "";
	}
	class'IrcRelayState'.static.StaticSaveConfig();
	TravelEndTime = Level.TimeSeconds + TravelTime;

	if (ircAddress == "" || ircPort == 0 || ircChannel == "" || ircNick == "")
		DebugLog("IRC relay is not configured, check ircAddress, ircPort, ircChannel and ircNick in ircRelay.ini", 1);
	else
		bEnabled = true;

	SetTimer(0.25, true);
}

event Timer()
{
	// UT99 has no hook for the map change, ServerTravel only sets the next URL
	if (!bTraveling && Level.NextURL != "")
		ServerTraveling();

	if (!bTraveling)
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
	local Pawn P;
	local PlayerPawn PP;
	local PlayerReplicationInfo PRI;
	local string Nick, Address;

	for (i = 0; i < PlayerCount; i++)
		Players[i].bSeen = false;

	for (P = Level.PawnList; P != None; P = P.NextPawn)
	{
		PP = PlayerPawn(P);
		if (PP == None || NetConnection(PP.Player) == None)
			continue;
		PRI = PP.PlayerReplicationInfo;
		if (PRI == None || PRI.bIsABot)
			continue;

		Nick = PRI.PlayerName;
		j = FindPlayer(PRI.PlayerID);
		if (j >= 0)
		{
			Players[j].bSeen = true;
			if (Players[j].Nick != Nick)
			{
				Queue(PlayerColor(PRI) $ Players[j].Nick $ Chr(15) $ " renamed to " $ PlayerColor(PRI) $ Nick);
				Players[j].Nick = Nick;
			}
			continue;
		}
		if (PlayerCount >= ArrayCount(Players))
			continue;

		Address = PlayerAddress(PP);
		Players[PlayerCount].PlayerID = PRI.PlayerID;
		Players[PlayerCount].Nick = Nick;
		Players[PlayerCount].Address = Address;
		Players[PlayerCount].bSeen = true;
		PlayerCount++;

		if (IsTravelPlayer(Address))
			continue;
		if (PRI.bIsSpectator)
			Queue(PlayerColor(PRI) $ Nick $ Chr(15) $ " joined as spectator from " $ Address);
		else
			Queue(PlayerColor(PRI) $ Nick $ Chr(15) $ " joined the game from " $ Address);
	}

	// UT99 mutators get no logout, so a player who is gone has left
	for (i = PlayerCount - 1; i >= 0; i--)
	{
		if (Players[i].bSeen)
			continue;
		Queue(Chr(15) $ Players[i].Nick $ Chr(15) $ " left the game");
		for (j = i; j < PlayerCount - 1; j++)
			Players[j] = Players[j + 1];
		PlayerCount--;
	}

	// players of the previous map who did not come back
	if (TravelCount > 0 && Level.TimeSeconds >= TravelEndTime)
	{
		for (i = 0; i < TravelCount; i++)
		{
			j = InStr(TravelPlayers[i], " ");
			if (j > 0)
				Queue(Chr(15) $ Mid(TravelPlayers[i], j + 1) $ Chr(15) $ " left the game");
		}
		TravelCount = 0;
	}
}

function ServerTraveling()
{
	local int i;

	bTraveling = true;

	// remember the players, so they are not announced again after the map change
	for (i = 0; i < ArrayCount(TravelPlayers); i++)
	{
		if (i < PlayerCount)
			class'IrcRelayState'.default.Players[i] = Players[i].Address $ " " $ Players[i].Nick;
		else
			class'IrcRelayState'.default.Players[i] = "";
	}
	class'IrcRelayState'.static.StaticSaveConfig();

	// the connection does not survive the map change, so send everything that is left
	FlushQueue(true);
	if (Link != None && Link.bOpened)
		Link.SendLine("QUIT :Map change");
}

function bool IsTravelPlayer(string Address)
{
	local int i, j;

	for (i = 0; i < TravelCount; i++)
	{
		if (Left(TravelPlayers[i], Len(Address) + 1) == (Address $ " "))
		{
			for (j = i; j < TravelCount - 1; j++)
				TravelPlayers[j] = TravelPlayers[j + 1];
			TravelCount--;
			return true;
		}
	}
	return false;
}

function int FindPlayer(int PlayerID)
{
	local int i;

	for (i = 0; i < PlayerCount; i++)
		if (Players[i].PlayerID == PlayerID)
			return i;
	return -1;
}

function string PlayerAddress(PlayerPawn PP)
{
	local string Address;
	local int i;

	Address = PP.GetPlayerNetworkAddress();
	i = InStr(Address, ":");
	if (i > 0)
		Address = Left(Address, i);
	return Address;
}

function string PlayerColor(PlayerReplicationInfo PRI)
{
	if (PRI.bIsSpectator)
		return Chr(3) $ "14";
	if (!Level.Game.bTeamGame)
		return Chr(15);
	switch (PRI.Team)
	{
		case 0:
			return Chr(3) $ "04";
		case 1:
			return Chr(3) $ "02";
		case 2:
			return Chr(3) $ "03";
		case 3:
			return Chr(3) $ "08";
	}
	return Chr(15);
}

//=============================================================================
// Game to IRC
//=============================================================================

// the message hooks are called once per receiver
function bool MutatorTeamMessage(Actor Sender, Pawn Receiver, PlayerReplicationInfo PRI, coerce string S, name Type, optional bool bBeep)
{
	if (PRI != None && (Type == 'Say' || Type == 'TeamSay'))
		ChatOnce(PRI, S, Type);

	return Super.MutatorTeamMessage(Sender, Receiver, PRI, S, Type, bBeep);
}

// spectators do not use TeamMessage, their chat is broadcast as "Name:Message"
function bool MutatorBroadcastMessage(Actor Sender, Pawn Receiver, out coerce string Msg, optional bool bBeep, out optional name Type)
{
	local PlayerPawn PP;
	local string Prefix;

	PP = Spectator(Sender);
	if (PP != None && NetConnection(PP.Player) != None && PP.PlayerReplicationInfo != None)
	{
		Prefix = PP.PlayerReplicationInfo.PlayerName $ ":";
		if (Left(Msg, Len(Prefix)) == Prefix)
			ChatOnce(PP.PlayerReplicationInfo, Mid(Msg, Len(Prefix)), 'Say');
	}

	return Super.MutatorBroadcastMessage(Sender, Receiver, Msg, bBeep, Type);
}

function ChatOnce(PlayerReplicationInfo PRI, string Msg, name Type)
{
	if (PRI == LastPRI && Msg == LastMsg && Type == LastType && Level.TimeSeconds == LastTime)
		return;

	LastPRI = PRI;
	LastMsg = Msg;
	LastType = Type;
	LastTime = Level.TimeSeconds;
	GameChat(PRI, Msg, Type == 'TeamSay');
}

function GameChat(PlayerReplicationInfo PRI, string Message, bool bTeam)
{
	local string Nick;

	if (PRI.bIsABot)
		return;

	Nick = PRI.PlayerName;
	if (bTeam)
		Nick = Nick $ " (team)";

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
	if (QueueCount >= ArrayCount(SendQueue))
		RemoveQueued();
	SendQueue[QueueCount++] = Message;
}

function RemoveQueued()
{
	local int i;

	for (i = 0; i < QueueCount - 1; i++)
		SendQueue[i] = SendQueue[i + 1];
	QueueCount--;
}

function FlushQueue(bool bAll)
{
	while (QueueCount > 0 && Link != None && Link.bJoined && (bAll || Level.TimeSeconds >= NextSendTime))
	{
		Link.SendLine("PRIVMSG #" $ ircChannel $ " :" $ SendQueue[0]);
		RemoveQueued();
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

	for (i = 0; i < ArrayCount(ircIgnore); i++)
	{
		if (ircIgnore[i] != "" && ircIgnore[i] ~= Nick)
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

	if (Left(Message, 8) == (Chr(1) $ "ACTION "))
	{
		Message = Mid(Message, 8);
		if (Right(Message, 1) == Chr(1))
			Message = Left(Message, Len(Message) - 1);
		GameMessage("* " $ StripIrc(Nick) $ " " $ StripIrc(Message) $ " *");
	}
	else
		GameMessage(StripIrc(Nick) $ ": " $ StripIrc(Message));
}

// messages tagged with a game, e.g. "[UT99] text", only go into this game
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
	local Pawn P;

	DebugLog(Message, 4);
	for (P = Level.PawnList; P != None; P = P.NextPawn)
		if (PlayerPawn(P) != None)
			PlayerPawn(P).ClientMessage(Message, 'Event');
}

// removes IRC formatting and control characters, they would show up as boxes in the game
// the fonts of the game only know Latin-1
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
		else if (c > 255)
			Result = Result $ "?";
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
	ircPort=6667
}
