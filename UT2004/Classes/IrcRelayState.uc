//=============================================================================
// IrcRelayState
// Keeps the players across a map change, so they are not announced again.
// Each entry is the address and the name of a player, separated by a space.
//=============================================================================
class IrcRelayState extends Object
	config(ircRelay);

var config array<string> Players;

defaultproperties
{
}
