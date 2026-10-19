//=============================================================================
// IrcBroadcastHandler
// Passes the chat of the players to the relay. A chained handler is asked
// once per receiver, so every message is passed only once.
//=============================================================================
class IrcBroadcastHandler extends BroadcastHandler;

var MutIrcRelay Relay;
var PlayerReplicationInfo LastPRI;
var string LastMsg;
var name LastType;
var float LastTime;

function bool AcceptBroadcastText(PlayerController Receiver, PlayerReplicationInfo SenderPRI, out string Msg, optional name Type)
{
	if (Relay != None && SenderPRI != None && (Type == 'Say' || Type == 'TeamSay'))
	{
		if (SenderPRI != LastPRI || Msg != LastMsg || Type != LastType || Level.TimeSeconds != LastTime)
		{
			LastPRI = SenderPRI;
			LastMsg = Msg;
			LastType = Type;
			LastTime = Level.TimeSeconds;
			Relay.GameChat(SenderPRI, Msg, Type == 'TeamSay');
		}
	}

	return Super.AcceptBroadcastText(Receiver, SenderPRI, Msg, Type);
}

defaultproperties
{
}
