public SharedPlugin __pl_level_start_heal = 
{
    name = "level_start_heal",
    file = "level_start_heal.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_level_start_heal_SetNTVOptional()
{

}
#endif

/**
 * @brief Called when a survivor is healed
 *
 * @param client		client index
 *
 * @noreturn
 */
forward void LevelStartHeal_OnHealed(int client);
