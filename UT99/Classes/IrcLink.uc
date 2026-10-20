//=============================================================================
// IrcLink
// The connection to the IRC server. Lines are sent and received as UTF-8.
// A new link is spawned for every connection attempt and every map.
//=============================================================================
class IrcLink extends TcpLink;

var MutIrcRelay Relay;
var byte RecvBuffer[512];
var int RecvLength;
var string CurrentNick;
var bool bOpened;
var bool bWelcomed;
var bool bJoined;
var bool bFailed;
var float StartTime;
var float LastReceive;
var int LoginStep;

const MaxLineBytes = 510;

function Connect()
{
	LinkMode = MODE_Binary;
	ReceiveMode = RMODE_Manual;
	StartTime = Level.TimeSeconds;
	CurrentNick = Relay.ircNick;

	Relay.DebugLog("Connecting to irc server " $ Relay.ircAddress $ ":" $ Relay.ircPort, 1);
	Resolve(Relay.ircAddress);
}

event Resolved(IpAddr Addr)
{
	if (Relay == None)
		return;

	Addr.Port = Relay.ircPort;
	if (BindPort() == 0)
	{
		Relay.DebugLog("Could not bind a local port for the irc connection", 1);
		bFailed = true;
		return;
	}
	if (!Open(Addr))
	{
		Relay.DebugLog("Could not open a connection to irc server " $ IpAddrToString(Addr), 1);
		bFailed = true;
	}
}

event ResolveFailed()
{
	if (Relay == None)
		return;

	Relay.DebugLog("Could not resolve irc server " $ Relay.ircAddress, 1);
	bFailed = true;
}

event Opened()
{
	if (Relay == None)
		return;

	bOpened = true;
	LastReceive = Level.TimeSeconds;
	Relay.DebugLog("Connected to irc server " $ Relay.ircAddress, 1);

	if (Relay.ircPass != "")
		SendLine("PASS " $ Relay.ircPass, "PASS ********");
	SendLine("NICK " $ CurrentNick);
	SendLine("USER ircrelay 0 * :UT99 ircRelay");
}

event Closed()
{
	if (Relay == None)
		return;

	Relay.DebugLog("Connection to irc server " $ Relay.ircAddress $ " closed", 1);
	bFailed = true;
}

// the login continues step by step, the server needs a moment after the welcome
event Timer()
{
	if (Relay == None || !bOpened)
		return;

	if (LoginStep == 1)
	{
		Authenticate();
		LoginStep = 2;
		SetTimer(1.0, false);
	}
	else if (LoginStep == 2)
	{
		SendLine("JOIN #" $ Relay.ircChannel);
		LoginStep = 3;
	}
}

function Authenticate()
{
	if (Relay.ircAuthType == "AuthServ")
		SendLine("PRIVMSG AuthServ :AUTH " $ Relay.ircNick $ " " $ Relay.ircAuthPass, "PRIVMSG AuthServ :AUTH " $ Relay.ircNick $ " ********");
	else if (Relay.ircAuthType == "NickServ")
		SendLine("PRIVMSG NickServ :IDENTIFY " $ Relay.ircAuthPass, "PRIVMSG NickServ :IDENTIFY ********");
	else if (Relay.ircAuthType == "Q")
		SendLine("PRIVMSG Q@CServe.quakenet.org :AUTH " $ Relay.ircNick $ " " $ Relay.ircAuthPass, "PRIVMSG Q@CServe.quakenet.org :AUTH " $ Relay.ircNick $ " ********");
}

//=============================================================================
// Receiving
//=============================================================================

// the data of the ReceivedBinary event arrives broken in 469, so it is read manually
event Tick(float DeltaTime)
{
	local byte B[255];
	local int Count, Reads;

	if (Relay == None || !bOpened)
		return;

	for (Reads = 0; Reads < 16; Reads++)
	{
		Count = ReadBinary(255, B);
		if (Count <= 0)
			break;
		ReceiveBytes(Count, B);
	}
}

function ReceiveBytes(int Count, byte B[255])
{
	local int i;

	LastReceive = Level.TimeSeconds;
	for (i = 0; i < Count; i++)
	{
		if (B[i] == 10)
		{
			ProcessLine(DecodeLine());
			RecvLength = 0;
		}
		else if (B[i] != 13 && RecvLength < ArrayCount(RecvBuffer))
			RecvBuffer[RecvLength++] = B[i];
	}
}

function ProcessLine(string Line)
{
	local string Prefix, Nick, Command, Params, Trailing, Target;
	local int i;

	if (Line == "")
		return;
	Relay.DebugLog("< " $ Line, 4);

	if (Left(Line, 1) == ":")
	{
		i = InStr(Line, " ");
		if (i < 0)
			return;
		Prefix = Mid(Line, 1, i - 1);
		Line = Mid(Line, i + 1);
	}

	i = InStr(Line, " :");
	if (i >= 0)
	{
		Trailing = Mid(Line, i + 2);
		Line = Left(Line, i);
	}

	i = InStr(Line, " ");
	if (i >= 0)
	{
		Command = Caps(Left(Line, i));
		Params = Mid(Line, i + 1);
	}
	else
		Command = Caps(Line);

	Nick = Prefix;
	i = InStr(Nick, "!");
	if (i >= 0)
		Nick = Left(Nick, i);

	Target = Params;
	i = InStr(Target, " ");
	if (i >= 0)
		Target = Left(Target, i);
	if (Target == "")
		Target = Trailing;

	switch (Command)
	{
		case "PING":
			if (Trailing != "")
				SendLine("PONG :" $ Trailing, , 4);
			else
				SendLine("PONG " $ Params, , 4);
			Relay.PingCount++;
			break;

		case "001":
			bWelcomed = true;
			if (Target != "")
				CurrentNick = Target;
			LoginStep = 1;
			SetTimer(1.0, false);
			break;

		case "433":
			if (!bWelcomed)
			{
				CurrentNick = CurrentNick $ "_";
				SendLine("NICK " $ CurrentNick);
			}
			break;

		case "NICK":
			if (Nick ~= CurrentNick)
				CurrentNick = Target;
			break;

		case "JOIN":
			if (Nick ~= CurrentNick && Target ~= ("#" $ Relay.ircChannel))
			{
				bJoined = true;
				Relay.DebugLog("Joined irc channel " $ Target, 1);
			}
			break;

		case "KICK":
			if (Target ~= ("#" $ Relay.ircChannel) && Mid(Params, Len(Target) + 1) ~= CurrentNick)
			{
				bJoined = false;
				Relay.DebugLog("Got kicked from irc channel " $ Target $ ": " $ Trailing, 1);
				LoginStep = 2;
				SetTimer(5.0, false);
			}
			break;

		case "PRIVMSG":
			if (Target ~= ("#" $ Relay.ircChannel))
				Relay.IrcChat(Nick, Trailing);
			break;

		case "ERROR":
			Relay.DebugLog("Irc server error: " $ Trailing, 1);
			break;

		case "403":
		case "471":
		case "473":
		case "474":
		case "475":
			Relay.DebugLog("Could not join irc channel #" $ Relay.ircChannel $ ": " $ Trailing, 1);
			break;
	}
}

// decodes the received line as UTF-8, or as Latin-1 if it is no valid UTF-8
function string DecodeLine()
{
	local string Result;
	local int i, j, c, Code, Extra;

	for (i = 0; i < RecvLength; i++)
	{
		c = RecvBuffer[i];
		if (c < 128)
		{
			if (c > 0)
				Result = Result $ Chr(c);
			continue;
		}

		if (c >= 194 && c <= 223)
		{
			Extra = 1;
			Code = c & 31;
		}
		else if (c >= 224 && c <= 239)
		{
			Extra = 2;
			Code = c & 15;
		}
		else if (c >= 240 && c <= 244)
		{
			Extra = 3;
			Code = c & 7;
		}
		else
			return DecodeLatin1();

		if (i + Extra >= RecvLength)
			return DecodeLatin1();
		for (j = 1; j <= Extra; j++)
		{
			if ((RecvBuffer[i + j] & 192) != 128)
				return DecodeLatin1();
			Code = (Code << 6) | (RecvBuffer[i + j] & 63);
		}
		i += Extra;

		// the game only knows 16 bit characters
		if (Code > 65535 || (Code >= 55296 && Code <= 57343))
			Result = Result $ "?";
		else
			Result = Result $ Chr(Code);
	}
	return Result;
}

function string DecodeLatin1()
{
	local string Result;
	local int i;

	for (i = 0; i < RecvLength; i++)
		if (RecvBuffer[i] > 0)
			Result = Result $ Chr(RecvBuffer[i]);
	return Result;
}

//=============================================================================
// Sending
//=============================================================================

// sends a line as UTF-8, cut to the maximum length of an IRC line
function SendLine(string Line, optional string DebugLine, optional int DebugLevel)
{
	local byte Data[512];
	local byte B[255];
	local int i, j, c, Length, Count;

	if (Relay == None || !bOpened)
		return;

	if (DebugLine == "")
		DebugLine = Line;
	if (DebugLevel == 0)
		DebugLevel = 3;
	Relay.DebugLog("> " $ DebugLine, DebugLevel);

	for (i = 0; i < Len(Line); i++)
	{
		c = Asc(Mid(Line, i, 1));
		if (c == 13 || c == 10 || c == 0)
			continue;

		if (c < 128)
		{
			if (Length + 1 > MaxLineBytes)
				break;
			Data[Length++] = c;
		}
		else if (c < 2048)
		{
			if (Length + 2 > MaxLineBytes)
				break;
			Data[Length++] = 192 | (c >> 6);
			Data[Length++] = 128 | (c & 63);
		}
		else
		{
			if (Length + 3 > MaxLineBytes)
				break;
			Data[Length++] = 224 | (c >> 12);
			Data[Length++] = 128 | ((c >> 6) & 63);
			Data[Length++] = 128 | (c & 63);
		}
	}
	Data[Length++] = 13;
	Data[Length++] = 10;

	for (i = 0; i < Length; i += Count)
	{
		Count = Min(255, Length - i);
		for (j = 0; j < Count; j++)
			B[j] = Data[i + j];
		SendBinary(Count, B);
	}
}

defaultproperties
{
}
