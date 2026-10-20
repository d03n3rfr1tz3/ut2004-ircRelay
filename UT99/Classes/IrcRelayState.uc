//=============================================================================
// IrcRelayState
// Keeps the players across a map change, so they are not announced again.
// Each entry is the address and the name of a player, separated by a space.
// The size matches TravelPlayers in MutIrcRelay.
//=============================================================================
class IrcRelayState extends Object
	config(ircRelay);

var config string Players[32];

defaultproperties
{
}
