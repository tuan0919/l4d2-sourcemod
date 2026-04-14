public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || entity >= MAX_TRACKED_EDICTS)
    {
        return;
    }

    if (StrContains(classname, "molotov_projectile", false) != -1)
    {
        g_bMolotovProjectile[entity] = true;
        RequestFrame(Frame_InitMolotovProjectile, EntIndexToEntRef(entity));
        return;
    }

    if (StrContains(classname, "inferno", false) != -1 || StrContains(classname, "entityflame", false) != -1)
    {
        RequestFrame(Frame_MarkFireEntitySource, EntIndexToEntRef(entity));
        return;
    }

    if (!ClassnameLooksHazard(classname))
    {
        return;
    }

    RequestFrame(Frame_DelayedHookHazard, EntIndexToEntRef(entity));
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity < MAX_TRACKED_EDICTS)
    {
        g_bHazardHooked[entity] = false;

        if (g_iHazardEntType[entity] != view_as<int>(Hazard_None))
        {
            int owner = 0;
            if ((GetGameTime() - g_fHazardLastHitTime[entity]) <= 3.0)
            {
                owner = g_iHazardLastOwner[entity];
            }
            AddSourceEvent(view_as<HazardType>(g_iHazardEntType[entity]), g_vHazardLastPos[entity], owner);
        }

        if (g_bMolotovProjectile[entity])
        {
            AddSourceEvent(Hazard_Molotov, g_vMolotovLastPos[entity], g_iMolotovOwner[entity]);
        }

        g_iHazardEntType[entity] = view_as<int>(Hazard_None);
        g_iHazardLastOwner[entity] = 0;
        g_fHazardLastHitTime[entity] = 0.0;
        g_vHazardLastPos[entity][0] = 0.0;
        g_vHazardLastPos[entity][1] = 0.0;
        g_vHazardLastPos[entity][2] = 0.0;
        g_bMolotovProjectile[entity] = false;
        g_iMolotovOwner[entity] = 0;
        g_vMolotovLastPos[entity][0] = 0.0;
        g_vMolotovLastPos[entity][1] = 0.0;
        g_vMolotovLastPos[entity][2] = 0.0;
        g_iFireEntSourceType[entity] = view_as<int>(Hazard_None);
        g_iFireEntOwner[entity] = 0;
        g_fFireEntMarkTime[entity] = 0.0;
    }
}
