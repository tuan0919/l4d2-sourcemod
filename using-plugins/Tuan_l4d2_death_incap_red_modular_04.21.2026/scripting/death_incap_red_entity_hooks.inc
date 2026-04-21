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

            // Ghi gascan explosion vào ring buffer riêng để inferno resolution dùng
            if (view_as<HazardType>(g_iHazardEntType[entity]) == Hazard_Gascan
                && (GetGameTime() - g_fHazardLastHitTime[entity]) <= 5.0)
            {
                int geIdx = g_iGascanExplodeWrite;
                g_iGascanExplodeOwner[geIdx] = owner;
                g_fGascanExplodeTime[geIdx]  = GetGameTime();
                g_vGascanExplodePos[geIdx][0] = g_vHazardLastPos[entity][0];
                g_vGascanExplodePos[geIdx][1] = g_vHazardLastPos[entity][1];
                g_vGascanExplodePos[geIdx][2] = g_vHazardLastPos[entity][2];
                g_iGascanExplodeWrite = (g_iGascanExplodeWrite + 1) % MAX_RECENT_GASCAN_EXPLODES;
            }
        }

        if (g_bMolotovProjectile[entity])
        {
            AddSourceEvent(Hazard_Molotov, g_vMolotovLastPos[entity], g_iMolotovOwner[entity]);

            // Ghi molotov destroy vào ring buffer riêng để inferno resolution dùng
            int mdIdx = g_iMolotovDestroyWrite;
            g_iMolotovDestroyOwner[mdIdx]    = g_iMolotovOwner[entity];
            g_fMolotovDestroyTime[mdIdx]     = GetGameTime();
            g_vMolotovDestroyPos[mdIdx][0]   = g_vMolotovLastPos[entity][0];
            g_vMolotovDestroyPos[mdIdx][1]   = g_vMolotovLastPos[entity][1];
            g_vMolotovDestroyPos[mdIdx][2]   = g_vMolotovLastPos[entity][2];
            g_iMolotovDestroyWrite = (g_iMolotovDestroyWrite + 1) % MAX_RECENT_MOLOTOV_DESTROYS;
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
        g_iFireEntSourceConfidence[entity] = view_as<int>(FireSourceConfidence_None);
        g_fFireEntMarkTime[entity] = 0.0;
        g_bFireEntRecheckQueued[entity] = false;
    }
}
