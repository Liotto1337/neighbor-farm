extends Node
## Global event bus. Every game-wide signal is declared here and nowhere else.

# Lifecycle / time
signal state_loaded
signal clock_tick(now: float)
signal save_requested
signal game_saved
signal welcome_back(summary: Dictionary)

# State changes (UI re-reads state when these fire)
signal currencies_changed(coins: int, seeds: int, feed: int)
signal xp_changed(level: int, xp_in_level: int, xp_needed: int)
signal level_up(new_level: int)
signal tiles_changed
signal selected_crop_changed(crop_id: String)
signal inventory_changed
signal animals_changed
signal buildings_changed
signal neighbors_changed
signal contract_changed
signal boost_changed(until: float)

# UI intents
signal tile_tapped(index: int)
signal tab_requested(tab_id: String)
signal modal_requested(modal_id: String, payload: Dictionary)
signal modal_close_requested
signal toast_requested(text: String)
signal neighbor_visit_requested(index: int)

# Monetization
signal purchase_started(sku: String)
signal purchase_completed(sku: String)
signal purchase_failed(sku: String, reason: String)
signal restore_completed(skus: Array)
signal ad_started(kind: String)
signal ad_rewarded_completed
signal ad_interstitial_closed
signal ad_failed(kind: String, reason: String)
