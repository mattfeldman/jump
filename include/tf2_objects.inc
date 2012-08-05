/**
 * vim: set ai et ts=4 sw=4 syntax=sourcepawn :
 * File: tf2_objects.inc
 * Description: Functions to return infomation about TF2 objects.
 * Author(s): Naris (Murray Wilson)
 */

#if defined _tf2_objects_included
 #endinput
#endif
#define _tf2_objects_included

enum TFObjectType
{
    TFObjectType_Dispenser = 0,
    TFObjectType_Teleporter,
    TFObjectType_Sentrygun,
    TFObjectType_TeleporterEntry,
    TFObjectType_TeleporterExit,
    TFObjectType_Amplifier,
    TFObjectType_Sapper,
    TFObjectType_Unknown
};

stock const String:TF2_ObjectClassNames[TFObjectType][] =
{
    "obj_dispenser",
    "obj_teleporter",
    "obj_sentrygun",
    "obj_teleporter", // _entrance
    "obj_teleporter", // _exit
    "obj_dispenser", // amplifier
    "obj_sapper",
    ""
};

stock const String:TF2_ObjectNames[TFObjectType][] =
{
    "Dispenser",
    "Teleporter",
    "Sentry Gun",
    "Teleporter Entrance",
    "Teleporter Exit",
    "Amplifier",
    "Sapper",
    ""
};

stock TF2_ObjectModes[TFObjectType] =
{
    -1, // dispenser
    -1, // teleporter (either)
    -1, // sentrygun
     0, // telporter_entrance
     1, // teleporter_exit
    -1, // amplifier
    -1, // sapper
    -1  // unknown
};

// Max Sentry Ammo for Level:          0,   1,   2,   3, max
stock const TF2_MaxSentryShells[]  = { 0, 100, 120, 144, 255 };
stock const TF2_MaxSentryRockets[] = { 0,   0,   0,  20,  64 };
stock const TF2_SentryHealth[]     = { 0, 150, 180, 216, 511 };

stock TFObjectType:TF2_GetObjectType(entity, bool:specific=false)
{
    decl String:class[32];
    if (GetEdictClassname(entity,class,sizeof(class)))
        return TF2_GetObjectTypeFromClass(entity, class, specific);
    else
        return TFObjectType_Unknown;
}

stock TFObjectType:TF2_GetObjectTypeFromClass(target, const String:class[], bool:specific=false)
{
    if (StrEqual(class, TF2_ObjectClassNames[TFObjectType_Sentrygun]))
        return TFObjectType_Sentrygun;
    else if (StrEqual(class, TF2_ObjectClassNames[TFObjectType_Dispenser]))
        return TFObjectType_Dispenser;
    else if (StrEqual(class, TF2_ObjectClassNames[TFObjectType_Teleporter]))
    {
        return (specific) ? (TFObjectType_TeleporterEntry + TFObjectType:GetEntProp(target, Prop_Send, "m_iObjectMode"))
                          : TFObjectType_Teleporter;
    }
    else if (StrEqual(class, TF2_ObjectClassNames[TFObjectType_Sapper]))
        return TFObjectType_Sapper;
    else
        return TFObjectType_Unknown;
}

