/*
Jump++ is a sourcemod plugin to assist in running a TF2 Jump Server
Copyright (C) 2010  Matthew Feldman (decaprime)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Please note codeblocks may be marked as required to be unmodified by anyone other than the copyright holder
for author attribution purposes as allowed by GPL Section 7(b)
*/

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#pragma semicolon 1
#define PLUGIN_VERSION  "0.6.2"
#define SQL_TABLE_NAME "jump"

new Handle:db;
#define VECTOR_SIZE 3
#define STORED_VECTORS 2
#define VECTOR_TYPES 2
enum Vector{
	Normal = 0, Timed = 1,
}
enum VectorType{
	Position =0, Angle = 1,
}
#define MAX_COURSES 15 //shitty way for now
#define NUM_CLASSES 10
#define INFO_FLAGS 8 //Length of the following enumeration
enum PlayerInfo{
	DontTeleport,
	ShownWelcomeMessage,
	DontHeal,
	DontResupply,
	InHardcore,
	InTimed,
	HideTimer,
	IsReady,
}
new bool:PlayerFlags[MAXPLAYERS+1][INFO_FLAGS]; //This is a plugin specific array of flags to be used internally.
new bool:CourseComplete[MAXPLAYERS+1][MAX_COURSES][NUM_CLASSES]; //Arbitrary number of CPs - they are only bools and 10 classes, this can be heavily optimized
new Float:SaveCache[MAXPLAYERS+1][STORED_VECTORS][VECTOR_TYPES][VECTOR_SIZE];

new Handle:PlayerTimer = INVALID_HANDLE; //Timer
new Handle:TimerHUD = INVALID_HANDLE; //Timer Hud
new bool:dbActive=false;
new Handle:CPNames;
new Handle:HelpPanel;
new Handle:teamEnforceFile;
new teamEnforce;
new offsetMainClip, rocketOwnerOffset, stickyOwnerOffset;
new Handle:g_Cvar_SaveAnglesMethod = INVALID_HANDLE;

static const TFClass_MaxAmmo[TFClassType][2][3] =
{
	{ {-1,  -1,  -1 },{-1,  -1, -1} },
	{ {32,  36,  -1 },{32,  -1, -1} }, // scout
	{ {25,  75,  -1 },{12,  -1, -1} }, // sniper
	{ {20,  32,  -1 },{-1,  -1, -1} }, // soldier
	{ {16,  24,  -1 },{-1,  -1, -1} }, // demo
	{ {150, -1,  -1 },{150, -1, -1} }, // medic
	{ {200, 32,  -1 },{200, -1, -1} }, // heavy
	{ {200, 32,  -1 },{200, 16, -1} }, // pyro
	{ {24,  -1,  -1 },{24,  -1, -1} }, // spy
	{ {32,  200, 200},{-1,  -1, -1} }  // engy
};
static const TFClass_MaxClip[TFClassType][2][2] = 
{
	{ {-1, -1},{-1, -1} },
	{ {6,  12},{2,  -1} }, // scout
	{ {-1, 25},{1,  -1} }, // sniper
	{ {4,  6 },{-1, -1} }, // soldier
	{ {4,  8 },{-1, -1} }, // demo
	{ {40, -1},{40, -1} }, // medic
	{ {-1, 6 },{-1, -1} }, // heavy
	{ {-1, 6 },{-1, -1} }, // pyro
	{ {6,  -1},{6,  -1} }, // spy
	{ {6,  12},{-1, -1} }  // engy
}; 

///////////////////////////////
/////////INCLUDE FILES/////////
///////////////////////////////
#include "jump++/markers.sp"
///////////////////////////////

//Author Attribution - Do not modify
public Plugin:myinfo = 
{
	name = "Jump++",
	author = "decaprime",
	description = "Location saving and more for TF2 Jumping",
	version = PLUGIN_VERSION,
	url = "http://www.decaprime.com"
};
public OnPluginStart(){
	teamEnforce = 1;
	//Events
	HookEvent("player_hurt", PlayerHurtCallback);
	HookEvent("player_spawn", PlayerSpawnCallback);
	HookEvent("player_changeclass",PlayerChangeClassCallback);
	HookEvent("player_death",PlayerDeathCallback);
	//HookEvent("controlpoint_starttouch", CPStartTouchCallback); replaced with markers.sp
	//HookEvent("player_disconnect", PlayerDisconnectedCallback, EventHookMode_Pre);
	HookEvent("player_team", PlayerTeamCallback,EventHookMode_Pre);
	HookEvent("teamplay_round_start", RoundStartCallback);
	
	//Commands
	RegConsoleCmd("say",ChatHandler);
	RegConsoleCmd("sayteam",ChatHandler);
	RegConsoleCmd("sm_jump_teleport", TeleportCmdCallback, "Teleports you to a saved location");
	RegConsoleCmd("sm_jump_save", SaveCmdCallback, "Saves your current location.");
	RegConsoleCmd("sm_jump_reset", ResetCmdCallback, "Resets your current class save.");
	RegConsoleCmd("sm_jump_start", StartCmdCallback, "Teleports you to the start of the map without resetting your save.");
	RegConsoleCmd("sm_jump_help", HelpCmdCallback, "Shows in-game help menu.");
	RegConsoleCmd("sm_jump_resupply", ResupplyCmdCallback, "Refills your ammo.");
	RegConsoleCmd("jm_teleport", TeleportCmdCallback, "(Legacy) Teleports you to a saved location");
	RegConsoleCmd("jm_saveloc", SaveCmdCallback, "(Legacy) Saves your current location.");	
	RegConsoleCmd("sm_jump_autohp", AutoHPCmdCallback, "Turn on or off automatic healing.");
	RegConsoleCmd("sm_jump_autoammo", AutoAmmoCmdCallback, "Turn on or off automatic resupply.");
	RegConsoleCmd("sm_jump_hardcore", HardcoreCmdCallback, "Turn on or off hardcore mode.");
	RegConsoleCmd("sm_jump_timer", TimerCmdCallback, "Turn on or off the timer display.");
	RegConsoleCmd("sm_jump_ready", ReadyCmdCallback, "Say while standing on green start marker to start a timed run.");
	RegConsoleCmd("sm_jump_stop", StopCmdCallback, "Stops current timed run.");
	RegConsoleCmd("sm_jump_stats", StatsCmdCallback, "Shows stats website.");
	RegConsoleCmd("sm_jump_credits", CreditsCmdCallback, "Shows plugin credits."); //Author Attribution - Do not modify
	RegAdminCmd("sm_jump_team_enforce", TeamEnforceCmdCallback,  ADMFLAG_ROOT, "Changes the team enforcing, 1 - default, 2 - force red, 3 - don't force");	
	
	RegAdminCmd("sm_course_save", CourseSaveCmdCallback,  ADMFLAG_ROOT, "Save marked as a named course.");
	RegAdminCmd("sm_course_mark_start", MarkStartCmdCallback,  ADMFLAG_ROOT, "Mark the start of a course.");
	RegAdminCmd("sm_course_mark_end", MarkEndCmdCallback,  ADMFLAG_ROOT, "Mark the end of a course.");
	RegAdminCmd("sm_course_load", CourseLoadCmdCallback,  ADMFLAG_ROOT, "Load courses.");
	
	
	//RegAdminCmd("sm_jump_debug", DebugCmdCallback,  ADMFLAG_ROOT, "Turns on debug processing.");
	
	
	rocketOwnerOffset = FindSendPropInfo("CTFProjectile_Rocket", "m_hOwnerEntity");
	stickyOwnerOffset = FindSendPropInfo("CTFGrenadePipebombProjectile", "m_hThrower");

	offsetMainClip = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
	teamEnforceFile = CreateKeyValues("maps");
	
	g_Cvar_SaveAnglesMethod = CreateConVar("sm_jump_savevertical", "1", "Whether to save players' up/down angles", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	AutoExecConfig(true, "jump++");
	
	//DB Connection
	new String:error[255];
	db = SQL_Connect("jump", true, error, sizeof(error));
	if (db == INVALID_HANDLE){
		LogError("DB failed to load");
	}
	else {
		dbActive = true;
	}
	JPrintAll(error);
	decl String:query[1024];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS %s(steamid VARCHAR(64) NOT NULL, map VARCHAR(64) NOT NULL, class TINYINT NOT NULL, id TINYINT NOT NULL, x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, UNIQUE (steamid, map, id, class));", SQL_TABLE_NAME);
	if(SQL_Query(db, query)== INVALID_HANDLE){
		LogError("Failed to Create DB");
	}
	
	//Initialize Timer Handle & HUD
	PlayerTimer = CreateTimer(1.0, PlayerTimerTick, _, TIMER_REPEAT);
	TimerHUD = CreateHudSynchronizer();
	//Build Help Panel
	HelpPanel = CreatePanel();
	SetPanelTitle(HelpPanel,"---Help---");
	DrawPanelText(HelpPanel,"Jump++ is an addon by decaprime to provide utility on jump maps.");
	DrawPanelText(HelpPanel,"All saved locations are by class, and persist after disconnect.");
	DrawPanelText(HelpPanel," ");
	DrawPanelText(HelpPanel,"Commands: (say these in chat)");
	DrawPanelText(HelpPanel,"!s - Saves current location/view.");
	DrawPanelText(HelpPanel,"!t - Teleports to saved location.");
	DrawPanelText(HelpPanel,"!reset - Resets currently saved location(just current class).");
	DrawPanelText(HelpPanel,"!start - Takes you to the start of the map without removing your save.");
	DrawPanelText(HelpPanel,"!ammo - Toggles auto ammo.");
	DrawPanelText(HelpPanel,"!hp - Toggles auto hp.");
	DrawPanelText(HelpPanel,"!hardcore - Toggles hardcore mode.");
	DrawPanelText(HelpPanel,"!timer - Toggles showing the timer.");
	DrawPanelText(HelpPanel,"!jump_help - This menu.");
	DrawPanelText(HelpPanel,"  ");
	DrawPanelText(HelpPanel,"Press 0 to close.");
	JPrintAll("Plugin Loaded");	
}
public OnPluginEnd(){
	CloseHandle(db);
	CloseHandle(HelpPanel);
	CloseHandle(PlayerTimer);
	CloseHandle(MarkingTrace);
}
public OnClientConnected(client){
	
}
public OnClientDisconnect(client){
	ClearPlayerData(client);
}

/*--Events--*/
public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	result = false;
	return Plugin_Continue;	
}
public PlayerHurtCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	
	if(PlayerFlags[client][InHardcore]) return; //Nonthing should happen in hardcore.
	
	new TFClassType:pClass = TF2_GetPlayerClass(client);
	if(!PlayerFlags[client][PlayerInfo:DontResupply])
	{
		if(pClass == TFClass_Soldier)
		{
			SetEntData(GetPlayerWeaponSlot(client, 0), offsetMainClip, 4);
		}
		else if(pClass == TFClass_DemoMan)
		{
			SetEntData(GetPlayerWeaponSlot(client, 1), offsetMainClip, 8);
			SetEntData(GetPlayerWeaponSlot(client, 0), offsetMainClip, 4);
		}
	}
	if(!PlayerFlags[client][PlayerInfo:DontHeal])
		CreateTimer(0.0, HealPlayerTimer, client);
}
public PlayerSpawnCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(PlayerFlags[client][InHardcore]) return; //Nonthing should happen in hardcore.
	
	if(PlayerFlags[client][PlayerInfo:DontTeleport]){
		PlayerFlags[client][PlayerInfo:DontTeleport]=false;
	}
	else {
		TeleportClient(client, false);
	}
	if(!PlayerFlags[client][PlayerInfo:ShownWelcomeMessage]){
		JPrint(client, "This server is running \x04Jump++ \x03by \x04decaprime\x03, type \x01!jump_help \x03for more info and commands.");
		PlayerFlags[client][PlayerInfo:ShownWelcomeMessage]=true;
	}
}
public PlayerChangeClassCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	ClearVectors(client);
	ClearPlayerMarkers(client); // markers.sp
	TF2_RespawnPlayer(client);
	
	if(dbActive){
		decl String:steamid[64], String:map[128], String:query[512];
		if(GetClientAuthString(client, steamid, sizeof(steamid)/2)){
			GetCurrentMap(map, sizeof(map)/2);
			SQL_EscapeString(db, map, map, sizeof(map));
			new class = GetEventInt(event, "class");
			Format(query,sizeof(query),"SELECT id, x, y, z FROM %s WHERE steamid='%s' and map='%s' and class='%d';", SQL_TABLE_NAME, steamid, map, class);
			SQL_TQuery(db, T_LookupCallback, query, client);
		}
	}
}
public PlayerDeathCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(0.0, RespawnTimer, client);
}
/*public CPStartTouchCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new area = GetEventInt(event,"area");
	new client = GetEventInt(event, "player");
	new TFClassType:class = TF2_GetPlayerClass(client);
	if(!CPReached[client][area][class]){		
		new String:cname[128], String:classname[64], String:output[512], String:cpname[128];//, String:timeString[64];
			
		GetArrayString(CPNames, area, cpname, sizeof(cpname));
		GetClientName(client, cname, sizeof(cname));
		TF2_GetClassString(class, classname, sizeof(classname));
		if(PlayerFlags[client][InHardcore] && class != TFClass_Pyro){
			Format(output, sizeof(output), "\x01%s\x03 has reached CP: \x01%s\x03 as a \x01%s %\x03 in \x02HARDCORE MODE.", cname, cpname, classname);
			EmitSoundToAll("item/cart_explode.wav");
		}
		else {
			if(class == TFClass_Pyro && PlayerFlags[client][InHardcore]){
				JPrint(client, "Sorry, there is nothing HARDCORE about Pyro.");
			}
			Format(output, sizeof(output), "\x01%s\x03 has reached CP: \x01%s\x03 as a \x01%s.", cname, cpname, classname);
			EmitSoundToAll("misc/freeze_cam.wav");
		}
		
		JPrintAll(output);
		CPReached[client][area][class] = true;
	}
	new index = -1;
	index = FindEntityByClassname(index,"team_control_point_master");
	if(IsValidEntity(index)){
		RemoveEdict(index);		
	}
}*/
/*public Action:PlayerDisconnectedCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	ClearPlayerData(client);
	PlayerFlags[client][PlayerInfo:ShownWelcomeMessage]=false;
}*/
public Action:PlayerTeamCallback(Handle:event, const String:name[], bool:dontBroadcast){
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	new team = GetEventInt(event,"team");
	//new oldTeam = GetEventInt(event, "oldteam");
	if((teamEnforce == 1 && TFTeam:team == TFTeam_Red) || (teamEnforce == 2 && TFTeam:team == TFTeam_Blue)){ //Don't force
		CreateTimer(0.0,ChangeteamTimer,client);
	}
	/* This will not work untill ChangeToSpecTimer somehow makes the player switch into free roam camera
	Additionally I think an array like {client, x, y, z, ax, ay, a,z} is a better argument to pass.
	Since datapacks are objects, but that is secondary and minor effiency increase.
	else if(TFTeam:team == TFTeam_Spectator && (TFTeam:oldTeam == TFTeam_Red || TFTeam:oldTeam == TFTeam_Blue))
	{
		new Float:origin[3];
		new Float:angles[3];
		GetClientAbsOrigin(client, origin);
		GetClientEyeAngles(client, angles);
		new Handle:datapack = CreateDataPack();
		WritePackCell(datapack, client); 
		WritePackFloat(datapack, origin[0]);
		WritePackFloat(datapack, origin[1]);
		WritePackFloat(datapack, origin[2]);
		WritePackFloat(datapack, angles[0]);
		WritePackFloat(datapack, angles[1]);
		WritePackFloat(datapack, angles[2]);
		CreateTimer(1.0, ChangeToSpecTimer, datapack);
	}
	*/
}
public Action:RoundStartCallback(Handle:event, const String:name[], bool:dontBroadcast){
	/*This doesn't work on a few maps for some reason, reverting to old method.
	new index = -1;
	while((index = FindEntityByClassname(index, ("trigger_capture_area"))) != -1){
		SetEntPropFloat(index, Prop_Data, "m_flCapTime", 0.5);
	}
	new index = -1;
	while((index = FindEntityByClassname(index, ("trigger_capture_area"))) != -1){
		SetEntPropFloat(index, Prop_Data, "m_flCapTime", 0.5);
		SetVariantString("2 0");
		AcceptEntityInput(index, "SetTeamCanCap");
		SetVariantString("3 0");
		AcceptEntityInput(index, "SetTeamCanCap");
	}*/
	ClearMarkers();
	LoadCourses(); //markers.sp
}
public OnMapStart(){
	PrecacheModel("models/props_gameplay/cap_point_base.mdl", true);
	PrecacheSound("misc/freeze_cam.wav");
	AddFileToDownloadsTable("sound/misc/freeze_cam.wav");
	PrecacheSound("item/cart_explode.wav");
	AddFileToDownloadsTable("sound/item/cart_explode.wav");
	new count = GetEntProp(FindEntityByClassname(-1, ("tf_objective_resource")) ,Prop_Data, "m_iNumControlPoints");
	if(count > 0){
		CPNames = CreateArray(128,count);
		new index = -1;
		while((index = FindEntityByClassname(index, ("team_control_point"))) != -1){
			new String:cpname[128]; 	
			new point=GetEntProp(index, Prop_Data, "m_iPointIndex");
			GetEntPropString(index, Prop_Data, "m_iszPrintName", cpname, sizeof(cpname));
			SetArrayString(CPNames, point, cpname);
			AcceptEntityInput(index, "HideModel", index, index);
		}
	}
	//Load keyvalues
	decl String:map[128];
	GetCurrentMap(map, sizeof(map));
	FileToKeyValues(teamEnforceFile, "jump_map_settings.txt");
	teamEnforce = KvGetNum(teamEnforceFile, map, 1);
	KvRewind(teamEnforceFile);
	//CreateTimer(5.0, CPTimer);
}
/*--Commands--*/
public Action:ChatHandler(client, args){
	decl String:text[256];
	GetCmdArgString(text,sizeof(text));
	StripQuotes(text);
	if(StrEqual("!s", text) || StrEqual("!jm_saveloc", text)){
		SaveClientLocation(client);
		return Plugin_Handled;
	}
	else if(StrEqual("!t", text) || StrEqual("!jm_teleport", text)){
		TeleportClient(client, true);
		return Plugin_Handled;
	}
	else if(StrEqual("!reset", text)){
		ResetLocation(client);
		return Plugin_Handled;
	}
	else if(StrEqual("!start", text)){
		StartLocation(client);
		return Plugin_Handled;
	}
	else if(StrEqual("!hp", text)){
		AutoHP(client, !PlayerFlags[client][PlayerInfo:DontHeal]);
		return Plugin_Handled;
	}
	else if(StrEqual("!ammo", text)){
		AutoAmmo(client, !PlayerFlags[client][PlayerInfo:DontResupply]);
		return Plugin_Handled;
	}
	else if(StrEqual("!hardcore", text)){
		SetHardcore(client, !PlayerFlags[client][PlayerInfo:InHardcore]);
		return Plugin_Handled;
	}
	else if(StrEqual("!timer", text)){
		SetTimer(client, !PlayerFlags[client][PlayerInfo:HideTimer]);
		return Plugin_Handled;
	}
	else if(StrEqual("!resupply", text)){
		Resupply(client);
		return Plugin_Handled;
	}
	else if(StrEqual("!ready", text)){
		CourseReady(client); //makers.sp
		return Plugin_Handled;
	}
	else if(StrEqual("!stop", text)){
		PlayerFlags[client][InTimed]=false;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action:TeleportCmdCallback(client, args){
	TeleportClient(client, true);
}
public Action:SaveCmdCallback(client, args){
	SaveClientLocation(client);
}
public Action:ResetCmdCallback(client, args){
	ResetLocation(client);
}
public Action:StartCmdCallback(client, args){
	StartLocation(client);
}
public Action:HelpCmdCallback(client, args){
	ShowHelp(client);
}
public Action:ResupplyCmdCallback(client, args){
	Resupply(client);
}
public Action:TeamEnforceCmdCallback(client, args){
	decl String:argstring[128];
	if(args < 1){
		ReplyToCommand(client,"Usage: sm_jump_team_enforce <number> where 1 - default, 2 - force red, 3 - don't force");
	}
	else {
		GetCmdArg(1, argstring, sizeof(argstring));
		new input = StringToInt(argstring);
		if(input > 0 && input < 4){
			decl String:map[128];
			teamEnforce = input;
			GetCurrentMap(map, sizeof(map));
			KvSetNum(teamEnforceFile, map, teamEnforce);
			KvRewind(teamEnforceFile);
			KeyValuesToFile(teamEnforceFile, "jump_map_settings.txt");
			
			for(new i = 1; i < MAXPLAYERS; i++){
				if(IsClientInGame(i)){
					if(teamEnforce == 1 && TFTeam:GetClientTeam(i) == TFTeam_Red)
						ChangeClientTeam(i, _:TFTeam_Blue);
					else if(teamEnforce == 2 && TFTeam:GetClientTeam(i) == TFTeam_Blue)
						ChangeClientTeam(i, _:TFTeam_Red);
				}
			}
		}
	}
	return Plugin_Handled;
}
public Action:AutoHPCmdCallback(client, args){
	decl String:argstring[8];
	if(args < 1)
	{
		ReplyToCommand(client, "Usage: sm_jump_autohp <0|1>");
	}
	else
	{
		GetCmdArg(1, argstring, sizeof(argstring));
		switch(StringToInt(argstring))
		{
			case 0: AutoHP(client, true);
			case 1: AutoHP(client, false);
			default:ReplyToCommand(client, "Usage: sm_jump_autohp <0|1>");
		}
	}
	return Plugin_Handled;
}
public Action:AutoAmmoCmdCallback(client, args){
	decl String:argstring[8];
	if(args < 1)
	{
		ReplyToCommand(client, "Usage: sm_jump_autoammo <0|1>");
	}
	else
	{
		GetCmdArg(1, argstring, sizeof(argstring));
		switch(StringToInt(argstring))
		{
			case 0: AutoAmmo(client, true);
			case 1: AutoAmmo(client, false);
			default:ReplyToCommand(client, "Usage: sm_jump_autohp <0|1>");
		}
	}
	return Plugin_Handled;
}
public Action:HardcoreCmdCallback(client, args){
	decl String:argstring[8];
	if(args < 1)
	{
		ReplyToCommand(client, "Usage: sm_jump_hardcore <0|1>");
	}
	else
	{
		GetCmdArg(1, argstring, sizeof(argstring));
		switch(StringToInt(argstring))
		{
			case 0: SetHardcore(client, false);
			case 1: SetHardcore(client, true);
			default:ReplyToCommand(client, "Usage: sm_jump_hardcore <0|1>");
		}
	}
	return Plugin_Handled;
}
public Action:TimerCmdCallback(client, args){
	decl String:argstring[8];
	if(args < 1)
	{
		ReplyToCommand(client, "Usage: sm_jump_timer <0|1>");
	}
	else
	{
		GetCmdArg(1, argstring, sizeof(argstring));
		switch(StringToInt(argstring))
		{
			case 0: SetTimer(client, false);
			case 1: SetTimer(client, true);
			default:ReplyToCommand(client, "Usage: sm_jump_timer <0|1>");
		}
	}
	return Plugin_Handled;
}
public Action:ReadyCmdCallback(client, args){
	CourseReady(client);
}
public Action:StopCmdCallback(client, args){
	PlayerFlags[client][InTimed]=false;
}
public Action:StatsCmdCallback(client, args){
	decl String:map[128], String:url[256];
	GetCurrentMap(map, sizeof(map)/2);
	Format(url, sizeof(url), "www.decaprime.com/jump/theme/index.php?map=%s", map);
	ShowMOTDPanel(client, "decaprime.com Jump Statistics", url, MOTDPANEL_TYPE_URL);
}
//Author Attribution - Do not modify
//This function will allow for all contributors to the project to be credited (in order by first contribution)
public Action:CreditsCmdCallback(client, args){
	JPrint(client, "Jump++ by decaprime");
	JPrint(client, "Contributions from: tkoi");
}
/*--Functions--*/
public SaveClientLocation(client){
	if(client !=0){
		if(!IsPlayerAlive(client)){
			JPrint(client, "Can't save location while dead.");
		}
		else if(PlayerFlags[client][InHardcore]){
			JPrint(client, "Can't save location in hardcore mode.");
		}
		else if(!((GetEntityFlags(client) & FL_ONGROUND) || (GetEntityFlags(client) & FL_INWATER))){
			JPrint(client, "Can't save location midair");
		}
		else if(GetEntProp(client, Prop_Send, "m_bDucked") == 1){
			JPrint(client, "Can't save location while crouching.");
		}
		else {
			if(PlayerFlags[client][InTimed]){
				GetClientAbsOrigin(client, SaveCache[client][Timed][Position]);
				if(GetConVarBool(g_Cvar_SaveAnglesMethod))
					GetClientEyeAngles(client, SaveCache[client][Timed][Angle]);
				else
					GetClientAbsAngles(client, SaveCache[client][Timed][Angle]);
			}
			else {
				new Float:flood[3];
				flood = SaveCache[client][Normal][Position];
				GetClientAbsOrigin(client, SaveCache[client][Normal][Position]);
				if(GetConVarBool(g_Cvar_SaveAnglesMethod))
					GetClientEyeAngles(client, SaveCache[client][Normal][Angle]);
				else
					GetClientAbsAngles(client, SaveCache[client][Normal][Angle]);
				if(!VectorEquals(flood, SaveCache[client][Normal][Position]) && dbActive){
					decl String:steamid[64], String:map[128], String:query[512], String:query2[512];
					if(GetClientAuthString(client, steamid, sizeof(steamid)/2)){
						GetCurrentMap(map, sizeof(map)/2);
						SQL_EscapeString(db, map, map, sizeof(map));
						new TFClassType:class = TF2_GetPlayerClass(client);
						Format(query, sizeof(query), "INSERT INTO %s VALUES('%s','%s',%d,%d,%f,%f,%f) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z);", SQL_TABLE_NAME, steamid, map, class, 0, SaveCache[client][Normal][Position][0], SaveCache[client][Normal][Position][1], SaveCache[client][Normal][Position][2]);
						SQL_TQuery(db, T_SaveCallback, query, client);
						Format(query2, sizeof(query2), "INSERT INTO %s VALUES('%s','%s',%d,%d,%f,%f,%f) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z);", SQL_TABLE_NAME, steamid, map, class, 1, SaveCache[client][Normal][Angle][0], SaveCache[client][Normal][Angle][1], SaveCache[client][Normal][Angle][2]);
						SQL_TQuery(db, T_SaveCallback, query2, client);
					}
				}
			}
			JPrint(client,"Location Saved.");
		}
	}
}
public bool:TeleportClient(client, bool:verbose){
	new bool:returnValue = false;
	new Vector:currentVector = Vector:Normal;
	if(PlayerFlags[client][InTimed])
		currentVector = Vector:Timed;
	if(!IsPlayerAlive(client)){
		if(verbose)
			JPrint(client, "Can't teleport while dead.");
	}
	else if(PlayerFlags[client][InHardcore]){
		if(verbose)
			JPrint(client, "No teleporting in hardcore mode.");
	}
	else if(IsZeroVector(client, currentVector)){
		if(verbose)
			JPrint(client, "Sorry, no save found.");
	}
	else if(PlayerFlags[client][IsReady]){
		JPrint(client, "Saves are seperate on timed runs.");
	}
	else {
		TeleportEntity(client, SaveCache[client][currentVector][Position], SaveCache[client][currentVector][Angle], Float:{0.0,0.0,0.0});
		returnValue = true;
	}
	return returnValue;
}
public ResetLocation(client){
	if(!IsPlayerAlive(client)){
		JPrint(client, "Can't reset location while dead.");
	}
	else {
		ClearPlayerData(client);
		decl String:steamid[64], String:map[128], String:query[512], String:query2[512];
		if(GetClientAuthString(client, steamid, sizeof(steamid)/2)){
			GetCurrentMap(map, sizeof(map)/2);
			SQL_EscapeString(db, map, map, sizeof(map));
			new TFClassType:class = TF2_GetPlayerClass(client);
			Format(query, sizeof(query), "INSERT INTO %s VALUES('%s','%s',%d,%d,%f,%f,%f) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z);", SQL_TABLE_NAME, steamid, map, class, 0, SaveCache[client][Normal][Position][0], SaveCache[client][Normal][Position][1], SaveCache[client][Normal][Position][2]);
			SQL_TQuery(db, T_SaveCallback, query, client);
			Format(query2, sizeof(query2), "INSERT INTO %s VALUES('%s','%s',%d,%d,%f,%f,%f) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z);", SQL_TABLE_NAME, steamid, map, class, 1, SaveCache[client][Normal][Angle][0], SaveCache[client][Normal][Angle][1], SaveCache[client][Normal][Angle][2]);
			SQL_TQuery(db, T_SaveCallback, query2, client);
		}
		TF2_RespawnPlayer(client);
		JPrint(client,"Your saved location has been reset.");
	}
	
}
public StartLocation(client){
	PlayerFlags[client][PlayerInfo:DontTeleport]=true;
	TF2_RespawnPlayer(client);
}
public ShowHelp(client){
	ShowMOTDPanel(client, "decaprime.com Jump Help", "www.decaprime.com/jump/help.html", MOTDPANEL_TYPE_URL);
	//SendPanelToClient(HelpPanel,client, TextPanelCallback,0);
}
public Resupply(client){
	if(PlayerFlags[client][InHardcore]){
		JPrint(client, "No resupply in hardcore mode.");
		return;
	}
	new iMaxHealth = TF2_GetPlayerResourceData(client, TFResource_MaxHealth);
	SetEntityHealth(client, iMaxHealth);
	GiveAmmo(client);
}
public AutoHP(client, bool:set){
	PlayerFlags[client][PlayerInfo:DontHeal] = set;
	if(set == false)
		JPrint(client, "Auto HP is now enabled.");
	else
		JPrint(client, "Auto HP is now disabled.");
}
public AutoAmmo(client, bool:set){
	PlayerFlags[client][PlayerInfo:DontResupply] = set;
	if(set == false)
		JPrint(client, "Auto Ammo is now enabled.");
	else
		JPrint(client, "Auto Ammo is now disabled.");
}
public SetHardcore(client, bool:set){
	PlayerFlags[client][PlayerInfo:InHardcore] = set;
	if(set == true){
		JPrint(client, "Hardcore mode is now enabled.");
		TF2_RespawnPlayer(client);
		ClearCoursesComplete(client);
	}
	else
		JPrint(client, "Hardcore mode is now disabled.");
}
public SetTimer(client, bool:set){
	PlayerFlags[client][PlayerInfo:HideTimer] = set;
	if(set == false)
		JPrint(client, "Timer will now be shown.");
	else
		JPrint(client, "Timer will now be hidden.");
}
public GiveAmmo(client){
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return;
	new TFClassType:class = TF2_GetPlayerClass(client);
	FillClientAmmo(client, class);
	FillClientClip(client, class);
}
public FillClientAmmo(client, TFClassType:class){
	new weapon;
	new ammoValue;
	for (new i = 0; i < sizeof(TFClass_MaxAmmo[][]); i++)
	{
		weapon = GetEntProp(GetPlayerWeaponSlot(client, i), Prop_Send, "m_iEntityLevel") != 1;
		ammoValue = TFClass_MaxAmmo[class][weapon][i];
		if (ammoValue != -1)
			SetEntData(client, FindSendPropInfo("CTFPlayer", "m_iAmmo") + ((i+1)*4), ammoValue);
	}
}
public FillClientClip(client, TFClassType:class){
	new weapon;
	new clipValue;
	for (new i = 0; i < sizeof(TFClass_MaxClip[][]); i++)
	{
		weapon = GetEntProp(GetPlayerWeaponSlot(client, i), Prop_Send, "m_iEntityLevel") != 1;
		clipValue = TFClass_MaxClip[class][weapon][i];
		if (clipValue != -1)
			SetEntData(GetPlayerWeaponSlot(client, i), FindSendPropInfo("CTFWeaponBase", "m_iClip1"), clipValue);
	}
}

/*--DB Callbacks--*/
public T_LookupCallback(Handle:owner, Handle:hndl, const String:error[], any:client){
	if(hndl == INVALID_HANDLE){
		LogError("Failed to read vectors from db: %s", error);
		return;
	}
	if(client != 0) {
		new bool:doTeleport = false;
		while(SQL_FetchRow(hndl)){
			doTeleport = true;
			new id = SQL_FetchInt(hndl,0);
			SaveCache[client][Normal][id][0] = SQL_FetchFloat(hndl, 1);
			SaveCache[client][Normal][id][1] = SQL_FetchFloat(hndl, 2);
			SaveCache[client][Normal][id][2] = SQL_FetchFloat(hndl, 3);
		}
		if(doTeleport){
			TeleportClient(client, false);
		}
	}
}
public T_SaveCallback(Handle:owner, Handle:hndl, const String:error[], any:client){
	if(hndl == INVALID_HANDLE){
		LogError("Failed to save vectors to db: %s", error);
		return;
	}
}

/*--Timers--*/
public Action:HealPlayerTimer(Handle:timer, any:client){
	new iMaxHealth = TF2_GetPlayerResourceData(client, TFResource_MaxHealth);
	SetEntityHealth(client, iMaxHealth);
}
public Action:RespawnTimer(Handle:timer, any:client){
	TF2_RespawnPlayer(client);
}
public Action:ChangeteamTimer(Handle:timer, any:client){
	if(teamEnforce == 1)
		ChangeClientTeam(client, _:TFTeam_Blue);
	else if(teamEnforce == 2)
		ChangeClientTeam(client, _:TFTeam_Red);
}
public Action:CPTimer(Handle:timer){
	new index = -1;
	index = FindEntityByClassname(index,"team_control_point_master");
	while(IsValidEntity(index)){
		RemoveEdict(index);
		index = FindEntityByClassname(index,"team_control_point_master");
	}
	if(index > 0){
		LogError("Could not remove team_control_point_master with id %d", index);
	}
	index = -1;
	index = FindEntityByClassname(index,"trigger_capture_area");
	if(IsValidEntity(index)){
		RemoveEdict(index);
		index = FindEntityByClassname(index,"trigger_capture_area");
	}
	if(index > 0){
		LogError("Could not remove trigger_capture_area with id %d", index);
	}
	index = -1;
	index = FindEntityByClassname(index,"team_control_point");
	if(IsValidEntity(index)){
		RemoveEdict(index);
		index = FindEntityByClassname(index,"team_control_point");
	}
	if(index > 0){
		LogError("Could not remove team_control_point with id %d", index);
	}
}
public Action:PlayerTimerTick(Handle: timer){
	new clientCount=GetMaxClients();
	SetHudTextParams(0.0, 0.0, 1.0, 255, 255, 255, 175);
	for(new i = 1; i <= clientCount; i++){
		if(IsClientInGame(i) && !PlayerFlags[i][PlayerInfo:HideTimer]){
			new target=i;
			if(TFTeam:GetClientTeam(i) == TFTeam_Spectator){
				//if(GetEntProp(i, Prop_Send, "m_iObserverMode")==6){ //don't show to freelook spectate };
				target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
				if(target > MAXPLAYERS || target < 1){
					target=i;
				}
			}
			if(PlayerFlags[target][InTimed]){
				new sec;
				new min;
				new ms = RoundToFloor((GetEngineTime()-PlayerTimes[target])*10);
				sec = RoundToFloor((ms+0.0)/10.0);
				//ms -= sec*10; 
				min = RoundToFloor((sec+0.0)/60.0);
				sec -= min*60;		
				ShowHudText(i, _:TimerHUD,"%02i:%02i", min, sec);
			}
		}
	}
}
public Action:ChangeToSpecTimer(Handle:timer, any:datapack){
	ResetPack(datapack, false);
	new client = ReadPackCell(datapack);
	new Float:origin[3];
	new Float:angles[3];
	origin[0] = ReadPackFloat(datapack);
	origin[1] = ReadPackFloat(datapack);
	origin[2] = ReadPackFloat(datapack);
	angles[0] = ReadPackFloat(datapack);
	angles[1] = ReadPackFloat(datapack);
	angles[2] = ReadPackFloat(datapack);
	CloseHandle(datapack);
	if(IsClientConnected(client))
		TeleportEntity(client, origin, angles, Float:{0.0,0.0,0.0});
}

/*--Panel and Menu Functions--*/
public TextPanelCallback(Handle:menu, MenuAction:action, param1, param2){
	//Nothing to callback since its just a text panel
}

/*--Utility Functions--*/
public ClearPlayerData(client){
	ClearCoursesComplete(client);
	ClearVectors(client);
	ClearFlags(client);
	ClearPlayerMarkers(client); //markers.sp
}
public ClearVector(_:client, Vector:vector){
	for(new i = 0; i < VECTOR_TYPES; i++){
		for(new j = 0; j < VECTOR_SIZE; j++){
			SaveCache[client][vector][i][j] = 0.0;
		}
	}
}
public ClearVectors(client){
	for(new i = 0; i < VECTOR_TYPES; i++){
		ClearVector(client, Vector:i);
		
	}
}
public ClearCoursesComplete(client){
	for(new i = 0; i < MAX_COURSES; i++){
		for(new j = 0; j < NUM_CLASSES; j++){
			CourseComplete[client][i][j] = false;
		}
	}
}
public ClearFlags(client){
	for(new i = 0; i < INFO_FLAGS; i++){
		PlayerFlags[client][i]=false;
	}
}
public bool:VectorEquals(Float:v1[3], Float:v2[3]){
	return (v1[0] == v2[0]) && (v1[1] == v2[1]) && (v1[2] == v2[2]);
}
public bool:IsZeroVector(client, Vector:vector){
	return (SaveCache[client][vector][Position][0] == 0.0) &&
			(SaveCache[client][vector][Position][1] == 0.0) &&
			(SaveCache[client][vector][Position][2] == 0.0);
}

//Print Functions
public JPrint(client, const String:myString[] , any:...)
{
	new String:myFormattedString[strlen(myString)+255];
	VFormat(myFormattedString, strlen(myString)+255, myString, 3);
	PrintToChat(client,"\x03[\x04J++\x03] \x03%s", myFormattedString);
}
public JPrintAll(const String:myString[] , any:...)
{
	new String:myFormattedString[strlen(myString)+255];
	VFormat(myFormattedString, strlen(myString)+255, myString, 2);
	PrintToChatAll("\x03[\x04J++\x03] \x03%s",myFormattedString);
}
public TF2_GetClassString(any:tfclass, String:class[], any:size){
	switch(tfclass){
		case TFClass_Unknown:
			strcopy(class, size, "Unknown");
		case TFClass_Scout:
			strcopy(class,size,"Scout");
		case TFClass_Sniper:
			strcopy(class,size,"Sniper");
		case TFClass_Soldier:
			strcopy(class,size,"Soldier");
		case TFClass_DemoMan:
			strcopy(class,size,"Demoman");
		case TFClass_Medic:
			strcopy(class,size,"Medic");
		case TFClass_Heavy:
			strcopy(class,size,"Heavy");
		case TFClass_Pyro:
			strcopy(class,size,"Pyro");
		case TFClass_Spy:
			strcopy(class,size,"Spy");
		case TFClass_Engineer:
			strcopy(class,size,"Engineer");
	}
}