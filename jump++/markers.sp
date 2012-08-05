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

//markers.sp contains most of the timed run functionality of Jump++

#define COURSE_TABLE "jump_courses"
#define TIME_TABLE "jump_times"

//This enumeration is used for both (Player|Course)Markers don't get confused
#define MARKER_FLAGS 3 //size of the following enumeration
enum {
	StartMarker=0,
	EndMarker = 1,
	Index=2, Course=2
}
new AmmoCount[MAXPLAYERS+1];
new Float:PlayerTimes[MAXPLAYERS+1];
new PlayerMarkers[MAXPLAYERS+1][MARKER_FLAGS];
new CourseMarkers[MAX_COURSES][MARKER_FLAGS];
new String:CourseNames[MAX_COURSES][128];
new CourseIndex=0;//the current blank index of CourseMarkers


//These are used for setting up placement of markers
new CurrentStartEntity = -1;
new CurrentEndEntity = -1;
new bool:MarkingStart = false;
new bool:MarkingEnd = false;
new _:MarkingClient = -1;
new Float:StartLocationCache[MAX_COURSES][3];
new Float:CurrentStartCoords[3];
new Float:CurrentEndCoords[3];
new Handle:MarkingTrace = INVALID_HANDLE;
new lastEntTracked = -1;
public OnEntityCreated(entity, const String:classname[]){
	if(strcmp(classname, "tf_projectile_rocket")==0){
		SDKHook(entity, SDKHookType:SDKHook_Spawn, RocketSpawned);
	}
	if(strcmp(classname, "tf_projectile_pipe_remote")==0){
		CreateTimer(0.0, StickySpawned, any:entity);
		//SDKHook(entity, SDKHookType:SDKHook_Spawn, StickySpawned);
	}
}
public RocketSpawned(entity){
	if(entity == lastEntTracked) return;
	lastEntTracked = entity;
	new client = GetEntDataEnt2(entity, rocketOwnerOffset);
	if(client > 0){
		AmmoCount[client]++;
		//JPrint(client, "Fired %d rockets.", AmmoCount[client]);
	}
}
public Action:StickySpawned(Handle:timer, any:entity){
	new client = GetEntDataEnt2(entity, stickyOwnerOffset);
	if(client > 0){
		AmmoCount[client]++;
		//JPrint(client, "Fired %d stickies.", AmmoCount[client]);
	}
}
public CourseReady(client){
	//If you have started a previous course and aren't currently on a start marker
	if(PlayerMarkers[client][Index] != -1 && PlayerMarkers[client][StartMarker] == -1){
		PlayerFlags[client][InTimed]=false;
		//Make sure we set the correct start marker
		PlayerMarkers[client][StartMarker]=CourseMarkers[PlayerMarkers[client][Index]][StartMarker];
		TeleportEntity(client, StartLocationCache[PlayerMarkers[client][Index]], NULL_VECTOR, NULL_VECTOR);
	}
	if(PlayerMarkers[client][StartMarker] != -1){		
		for(new i=0; i < MAX_COURSES;i++){
			if(CourseMarkers[i][StartMarker]==PlayerMarkers[client][StartMarker]){		
				PlayerFlags[client][IsReady] = true;
				PlayerMarkers[client][Index] = i; //cache this index so we don't need to do this loop again
				PlayerMarkers[client][EndMarker] = CourseMarkers[i][EndMarker];
				ClearVector(client, Vector:Timed); //jump++.sp
				JPrint(client,"Timer for \x01%s\x03 will start when you leave this pad.", CourseNames[i]);
				break;
			}
		}
		
	}
}
public ClearPlayerMarkers(client){
	PlayerFlags[client][InTimed] = false;
	PlayerFlags[client][IsReady] = false;
	PlayerTimes[client] = 0.0;	
	PlayerMarkers[client][StartMarker] = -1;
	PlayerMarkers[client][EndMarker] = -1;
	PlayerMarkers[client][Index] = -1;
}
public AddCourse(id, Float:start[3], Float:end[3], String:name[]){
	CreateMarker(start, true);
	CreateMarker(end, false);
	start[2]+=40;//Constant lift to make hit detection more full since a player can't exist under this height
	end[2]+=40;
	new startEnt = CreateTouchMarker(start);
	new endEnt = CreateTouchMarker(end);
	start[2]-=40;
	end[2]-=40;
	if(IsValidEntity(startEnt) && IsValidEntity(endEnt) && CourseIndex < MAX_COURSES){
		SDKHook(startEnt, SDKHookType:SDKHook_StartTouch, SDKHookCB:OnStartStartTouch);
		SDKHook(startEnt, SDKHookType:SDKHook_EndTouch, SDKHookCB:OnStartEndTouch);
		SDKHook(endEnt, SDKHookType:SDKHook_StartTouch, SDKHookCB:OnEndStartTouch);
		StartLocationCache[CourseIndex]=start;
		CourseMarkers[CourseIndex][StartMarker]=startEnt;
		CourseMarkers[CourseIndex][EndMarker]=endEnt;
		CourseMarkers[CourseIndex][Course]=id;
		strcopy(CourseNames[CourseIndex], 128, name);//not a fan of this
		CourseIndex++;
	}
}
//When player starts standing on a start marker
public OnStartStartTouch(entity, client){
	PlayerMarkers[client][StartMarker] = entity;
}
//When player stops standing on a start marker
public OnStartEndTouch(entity, client){
	//the second should never evaluate false unless for some reason the entities are overlapping
	if(PlayerFlags[client][IsReady] && PlayerMarkers[client][StartMarker]==entity){
		PlayerTimes[client] = GetEngineTime();
		AmmoCount[client] = 0;
		PlayerFlags[client][InTimed] = true;	
		//print something here would be nice
		//JPrint(client,CourseNames[PlayerMarkers[client][Index]]);
	}
	PlayerMarkers[client][StartMarker] = -1;
	//ClearMarkers(client); shoudln't be neccesary
	PlayerFlags[client][IsReady] = false; // if you step off you're no longer ready
}
//When player starts standing on an end marker
public OnEndStartTouch(entity, client){
	if(entity==PlayerMarkers[client][EndMarker] && PlayerFlags[client][InTimed]){ //the associated end, second should always be true for now
	
		new String:cname[128], String:classname[64], String:steamid[64], String:query[1024], TFClassType:class, hardcore=0;
		class = TF2_GetPlayerClass(client);
		if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
			return
		GetClientName(client, cname, sizeof(cname));
		TF2_GetClassString(class, classname, sizeof(classname)/2-1);		
		new ms, sec, min;
		new time = RoundToFloor((GetEngineTime()-PlayerTimes[client])*10);
		ms = time;
		sec = RoundToFloor((ms+0.0)/10.0);
		ms -= sec*10; 
		min = RoundToFloor((sec+0.0)/60.0);
		sec -= min*60;
		
		if(PlayerFlags[client][InHardcore]){
			hardcore = 1;
			JPrintAll("\x01%s\x03 has completed \x01%s\x03 as a \x01%s \x03in \x01%02i\x03:\x01%02i\x03.\x01%02i\x03 in\x02 hardcore mode", cname, CourseNames[PlayerMarkers[client][Index]], classname, min, sec, ms);
			EmitSoundToAll("item/cart_explode.wav");
		}
		else {
			JPrintAll("\x01%s\x03 has completed \x01%s\x03 as a \x01%s \x03in \x01%02i\x03:\x01%02i\x03.\x01%i\x03", cname, CourseNames[PlayerMarkers[client][Index]], classname, min, sec, ms);
			EmitSoundToAll("misc/freeze_cam.wav");
		}
		if(GetClientAuthString(client, steamid, sizeof(steamid))){
			SQL_EscapeString(db, cname, cname, sizeof(cname));
			Format(query, sizeof(query), "INSERT INTO %s VALUES(NULL, %d,'%s','%s',%d,%d,%d,%d, NULL);", TIME_TABLE,
																CourseMarkers[PlayerMarkers[client][Index]][Course],
																	cname, steamid, class, AmmoCount[client], hardcore, time);
			SQL_TQuery(db, T_TimeSaveCallback, query);
		}
		CourseComplete[client][PlayerMarkers[client][Index]][class] = true;		
		
		//Looks ugly, but probably the most efficient as its called rarely
		new temp=PlayerMarkers[client][Index];
		ClearPlayerMarkers(client);
		PlayerMarkers[client][Index]=temp;		
	}
	else {
		if(IsPlayerAlive(client)){
			for(new i=0; i < MAX_COURSES;i++){
				if(CourseMarkers[i][EndMarker]==entity){
					new TFClassType:class=TF2_GetPlayerClass(client);
					if(!CourseComplete[client][i][class]){
						CourseComplete[client][i][class] = true;
						new String:cname[128], String:classname[64], String:steamid[64], String:query[1024], hardcore=0;			
						
						GetClientName(client, cname, sizeof(cname));
						TF2_GetClassString(class, classname, sizeof(classname));
						if(PlayerFlags[client][InHardcore]){
							JPrintAll("\x01%s\x03 has completed \x01%s\x03 as a \x01%s\x03 in \x02hardcore mode", cname, CourseNames[i], classname);
							EmitSoundToAll("item/cart_explode.wav");
							hardcore = 1;
						}
						else {
							JPrintAll("\x01%s\x03 has completed \x01%s\x03 as a \x01%s", cname, CourseNames[i], classname);
							EmitSoundToAll("misc/freeze_cam.wav");
						}							
						if(GetClientAuthString(client, steamid, sizeof(steamid))){
							SQL_EscapeString(db, cname, cname, sizeof(cname));
							Format(query, sizeof(query), "INSERT INTO %s VALUES(NULL, %d,'%s','%s',%d,%d,%d,%d, NULL);", TIME_TABLE,
																				CourseMarkers[i][Course],
																					cname, steamid, class, -1, hardcore, -1);
							SQL_TQuery(db, T_TimeSaveCallback, query);
						}
					}
					break;
				}
			}
		}
		else {
			//JPrint(client, "DEAD PLAYERS TOUCH THINGS!");
		}
		//You reached the end normally, as a non-timed run, spit some message out
	}
}
public _:CreateMarker(Float:coords[3], bool:isStart){
	new marker = CreateEntityByName("prop_dynamic_override");
	if(IsValidEntity(marker)){		
		SetEntityModel(marker, "models/props_gameplay/cap_point_base.mdl");
		DispatchSpawn(marker);
		if(isStart){
			SetEntityRenderColor(marker, 0, 255, 0, 255);
		}
		else {
			SetEntityRenderColor(marker, 255, 0, 0, 255);			
		}
		/*Shoudln't even register that it has collisions, just for show
		SetEntProp(marker, Prop_Data, "m_CollisionGroup", 0);
		SetEntProp(marker, Prop_Data, "m_usSolidFlags", 28);
		SetEntProp(marker, Prop_Data, "m_nSolidType", 6);		
		SetEntProp(marker, Prop_Data, "m_takedamage", 0, 1);
		AcceptEntityInput(marker, "DisableMotion", marker, marker);*/
		TeleportEntity(marker, coords, NULL_VECTOR, NULL_VECTOR);
	}
	else {
		marker = -1;
	}
	return marker;
}
public _:CreateTouchMarker(Float:coords[3]){	
	new marker = CreateEntityByName("item_healthkit_full");
	if(IsValidEntity(marker)){				
		DispatchSpawn(marker);
		SetEntityModel(marker, "models/props_gameplay/cap_point_base.mdl");		
		AcceptEntityInput(marker, "Disable");	
		TeleportEntity(marker, coords, NULL_VECTOR, NULL_VECTOR);
	}
	else {
		marker = -1;
	}
	return marker;
}
public Action:CourseLoadCmdCallback(client, args){
	decl String:map[128], String:query[512];
	GetCurrentMap(map, sizeof(map)/2);
	SQL_EscapeString(db, map, map, sizeof(map));
	Format(query, sizeof(query), "SELECT * FROM jump_courses WHERE map='%s'",map);
	SQL_TQuery(db, T_CourseLookupCallback, query);
}
public LoadCourses(){
	decl String:map[128], String:query[512];
	GetCurrentMap(map, sizeof(map)/2);
	SQL_EscapeString(db, map, map, sizeof(map));
	Format(query, sizeof(query), "SELECT * FROM jump_courses WHERE map='%s'",map);
	SQL_TQuery(db, T_CourseLookupCallback, query);
}
public T_CourseLookupCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE){
		LogError("Failed to read courses from db: %s", error);
		return;
	}
	CourseIndex=0;
	while(SQL_FetchRow(hndl)){
		new Float:start[3], Float:end[3];		
		new String:name[128];
		new id = SQL_FetchInt(hndl,0);
		SQL_FetchString(hndl, 2, name, sizeof(name));
		start[0] = SQL_FetchFloat(hndl, 3);
		start[1] = SQL_FetchFloat(hndl, 4);
		start[2] = SQL_FetchFloat(hndl, 5);
		end[0] = SQL_FetchFloat(hndl, 6);
		end[1] = SQL_FetchFloat(hndl, 7);
		end[2] = SQL_FetchFloat(hndl, 8);		
		AddCourse(id, start, end, name);
	}
}
public T_TimeSaveCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE){
		LogError("Failed to save time to db: %s", error);
		return;
	}
}
public ClearMarkers(){
	if(IsValidEdict(CurrentStartEntity))
		RemoveEdict(CurrentStartEntity);
	if(IsValidEdict(CurrentEndEntity))
		RemoveEdict(CurrentEndEntity);
	CurrentStartEntity = -1;
	CurrentEndEntity = -1;
	MarkingStart = false;
	MarkingEnd = false;
	MarkingClient = -1;
}
public Action:CourseSaveCmdCallback(client, args){	
	if(args == 1){
		if(CurrentStartEntity > 0 && CurrentEndEntity > 0){
			if(IsValidEntity(CurrentStartEntity) && IsValidEntity(CurrentEndEntity)){
				decl String:name[128], String:map[128], String:query[512];
				GetCmdArg(1, name, sizeof(name)/2);
				SQL_EscapeString(db, name, name, sizeof(name));
				GetCurrentMap(map, sizeof(map)/2);
				SQL_EscapeString(db, map, map, sizeof(map));
				Format(query, sizeof(query), "INSERT INTO %s VALUES(NULL,'%s','%s',%f,%f,%f,%f,%f,%f);", COURSE_TABLE, map, name, CurrentStartCoords[0], CurrentStartCoords[1], CurrentStartCoords[2], CurrentEndCoords[0], CurrentEndCoords[1], CurrentEndCoords[2]);
				SQL_LockDatabase(db);
				if(SQL_FastQuery(db, query)){
					new id = SQL_GetInsertId(db);
					ClearMarkers();
					AddCourse(id, CurrentStartCoords, CurrentEndCoords, name);
				}
				else {
					SQL_GetError(db, query, sizeof(query));
					JPrint(client, query);
				}
				SQL_UnlockDatabase(db);
			}
		}
		else {
			JPrint(client, "You must mark a valid start and end.");
		}
	}	
	else {
		JPrint(client,"You must specify a course name as a quoted string.");
	}
}
public Action:MarkStartCmdCallback(client, args){
	if(CurrentStartEntity == -1){
		GetClientAbsOrigin(client, CurrentStartCoords);
		CurrentStartEntity = CreateMarker(CurrentStartCoords, true);
	}
	MarkingStart = !MarkingStart;
	MarkingEnd = false;
	MarkingClient = client;
}
public Action:MarkEndCmdCallback(client, args){
	if(CurrentEndEntity == -1){
		GetClientAbsOrigin(client, CurrentEndCoords);
		CurrentEndEntity = CreateMarker(CurrentEndCoords, false);
	}
	MarkingEnd = !MarkingEnd;
	MarkingStart = false;
	MarkingClient = client;
}
public bool:TraceRayDontHitSelf(entity, mask){
	if(entity == MarkingClient || entity==CurrentStartEntity || entity==CurrentEndEntity)
		return false;
	return true;
}
public OnGameFrame(){
	if(MarkingStart || MarkingEnd){
		new Float:eyePos[3], Float:eyeAng[3];
		GetClientEyePosition(MarkingClient, eyePos);
		GetClientEyeAngles(MarkingClient, eyeAng);
		MarkingTrace=TR_TraceRayFilterEx(eyePos, eyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf);
		if(TR_DidHit(MarkingTrace)){				
			if(MarkingStart){
				TR_GetEndPosition(CurrentStartCoords, MarkingTrace);
				TeleportEntity(CurrentStartEntity, CurrentStartCoords, Float:{0.0,0.0,0.0}, NULL_VECTOR);
			}
			else {
				TR_GetEndPosition(CurrentEndCoords, MarkingTrace);
				TeleportEntity(CurrentEndEntity, CurrentEndCoords, Float:{0.0,0.0,0.0}, NULL_VECTOR);
			}
		}
	}
}