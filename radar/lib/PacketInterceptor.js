'use strict';

/**
 * PacketInterceptor class for handling network packet interception
 * Hooks into TERA network packets for position and entity data
 */
class PacketInterceptor {
    constructor(mod, dataProcessor, entityTracker) {
        this.mod = mod;
        this.dataProcessor = dataProcessor;
        this.entityTracker = entityTracker;
        
        // Player state tracking
        this.playerPosition = null;
        this.playerRotation = null;
        this.playerAimData = null;
        
        // Hook initialization flag
        this.hooksInitialized = false;
    }

    /**
     * Initialize all packet hooks
     */
    initializeHooks() {
        if (this.hooksInitialized) {
            this.mod.log('[PacketInterceptor] Hooks already initialized');
            return;
        }

        try {
            this.setupPlayerLocationHooks();
            this.setupEntitySpawnHooks();
            this.setupEntityDespawnHooks();
            this.setupEntityMovementHooks();
            this.setupEntityHealthHooks();
            
            this.hooksInitialized = true;
            this.mod.log('[PacketInterceptor] All packet hooks initialized successfully');
        } catch (error) {
            this.mod.error(`[PacketInterceptor] Failed to initialize hooks: ${error.message}`);
        }
    }

    /**
     * Set up player location and aim packet hooks
     */
    setupPlayerLocationHooks() {
        // Hook into C_PLAYER_LOCATION for position updates
        this.mod.hook('C_PLAYER_LOCATION', 5, (event) => {
            this.onPlayerLocation(event);
        });

        // Hook into C_USER_AIM for precise rotation data
        this.mod.hook('C_USER_AIM', 1, (event) => {
            this.onPlayerAim(event);
        });
    }

    /**
     * Set up entity spawn packet hooks
     */
    setupEntitySpawnHooks() {
        // Hook into S_SPAWN_USER for player spawns
        this.mod.hook('S_SPAWN_USER', this.mod.majorPatchVersion >= 99 ? 16 : 15, (event) => {
            this.onEntitySpawn(event, 'user');
        });

        // Hook into S_SPAWN_NPC for NPC/Monster spawns
        this.mod.hook('S_SPAWN_NPC', 11, (event) => {
            this.onEntitySpawn(event, 'npc');
        });
    }

    /**
     * Set up entity despawn packet hooks
     */
    setupEntityDespawnHooks() {
        // Hook into S_DESPAWN_USER for player despawns
        this.mod.hook('S_DESPAWN_USER', 3, (event) => {
            this.onEntityDespawn(event, 'user');
        });

        // Hook into S_DESPAWN_NPC for NPC/Monster despawns
        this.mod.hook('S_DESPAWN_NPC', 3, (event) => {
            this.onEntityDespawn(event, 'npc');
        });
    }

    /**
     * Set up entity movement packet hooks
     */
    setupEntityMovementHooks() {
        // Hook into S_USER_LOCATION for player movement updates
        const userLocationVersion = this.mod.majorPatchVersion >= 105 ? 6 : 5;
        this.mod.hook('S_USER_LOCATION', userLocationVersion, (event) => {
            this.onEntityMove(event, 'user');
        });

        // Hook into S_NPC_LOCATION for NPC movement updates
        this.mod.hook('S_NPC_LOCATION', 3, (event) => {
            this.onEntityMove(event, 'npc');
        });
    }

    /**
     * Set up entity health packet hooks
     */
    setupEntityHealthHooks() {
        // Hook into S_CREATURE_CHANGE_HP for health status updates
        this.mod.hook('S_CREATURE_CHANGE_HP', 6, (event) => {
            this.onHealthChange(event);
        });
    }

    /**
     * Handle player location updates
     * @param {Object} event - C_PLAYER_LOCATION packet data
     */
    onPlayerLocation(event) {
        try {
            const processedData = this.dataProcessor.processPlayerLocation(event);
            
            if (processedData) {
                this.playerPosition = processedData.position;
                this.playerRotation = processedData.rotation;
                
                // Update entity tracker with player position
                this.entityTracker.setPlayerPosition(this.playerPosition);
                
                this.mod.log(`[PacketInterceptor] Player position updated: ${JSON.stringify(this.playerPosition)}`);
            }
        } catch (error) {
            this.mod.error(`[PacketInterceptor] Error processing player location: ${error.message}`);
        }
    }

    /**
     * Handle player aim updates
     * @param {Object} event - C_USER_AIM packet data
     */
    onPlayerAim(event) {
        try {
            const processedData = this.dataProcessor.processPlayerAim(event);
            
            if (processedData) {
                this.playerAimData = processedData;
                
                this.mod.log(`[PacketInterceptor] Player aim updated: yaw=${processedData.yaw}, pitch=${processedData.pitch}`);
            }
        } catch (error) {
            this.mod.error(`[PacketInterceptor] Error processing player aim: ${error.message}`);
        }
    }

    /**
     * Handle entity spawn events
     * @param {Object} event - S_SPAWN_USER or S_SPAWN_NPC packet data
     * @param {string} entityType - 'user' or 'npc'
     */
    onEntitySpawn(event, entityType) {
        try {
            // Skip processing if event is null or undefined (packet parsing failed)
            if (!event) {
                return;
            }
            
            // Add entity type information to the event data
            const enhancedEvent = {
                ...event,
                isPlayer: entityType === 'user',
                isNPC: entityType === 'npc' && (!event.aggressive && event.relation !== 12),
                isMonster: entityType === 'npc' && (event.aggressive || event.relation === 12)
            };

            const processedData = this.dataProcessor.processEntitySpawn(enhancedEvent);
            
            if (processedData) {
                const entity = this.entityTracker.addEntity(processedData);
                
                if (entity) {
                    this.mod.log(`[PacketInterceptor] Entity spawned: ${entity.name} (${entity.type}) at ${JSON.stringify(entity.position)}`);
                }
            }
        } catch (error) {
            // Only log non-parsing errors to avoid spam
            if (!error.message.includes('Offset is outside the bounds')) {
                this.mod.error(`[PacketInterceptor] Error processing entity spawn: ${error.message}`);
            }
        }
    }

    /**
     * Handle entity despawn events
     * @param {Object} event - S_DESPAWN_USER or S_DESPAWN_NPC packet data
     * @param {string} entityType - 'user' or 'npc'
     */
    onEntityDespawn(event, entityType) {
        try {
            const processedData = this.dataProcessor.processEntityDespawn(event);
            
            if (processedData && processedData.gameId) {
                const removed = this.entityTracker.removeEntity(processedData.gameId);
                
                if (removed) {
                    this.mod.log(`[PacketInterceptor] Entity despawned: gameId=${processedData.gameId}`);
                }
            }
        } catch (error) {
            this.mod.error(`[PacketInterceptor] Error processing entity despawn: ${error.message}`);
        }
    }

    /**
     * Handle entity movement updates
     * @param {Object} event - S_USER_LOCATION or S_NPC_LOCATION packet data
     * @param {string} entityType - 'user' or 'npc'
     */
    onEntityMove(event, entityType) {
        try {
            // Skip processing if event is null or undefined (packet parsing failed)
            if (!event) {
                return;
            }
            
            const processedData = this.dataProcessor.processEntityMovement(event);
            
            if (processedData && processedData.gameId) {
                const updated = this.entityTracker.updateEntityPosition(
                    processedData.gameId, 
                    processedData.position
                );
                
                if (updated) {
                    this.mod.log(`[PacketInterceptor] Entity moved: gameId=${processedData.gameId} to ${JSON.stringify(processedData.position)}`);
                }
            }
        } catch (error) {
            // Only log non-parsing errors to avoid spam
            if (!error.message.includes('Offset is outside the bounds')) {
                this.mod.error(`[PacketInterceptor] Error processing entity movement: ${error.message}`);
            }
        }
    }

    /**
     * Handle entity health changes
     * @param {Object} event - S_CREATURE_CHANGE_HP packet data
     */
    onHealthChange(event) {
        try {
            const processedData = this.dataProcessor.processEntityHealthChange(event);
            
            if (processedData && processedData.gameId) {
                const updated = this.entityTracker.updateEntityHealth(
                    processedData.gameId,
                    processedData.hp,
                    processedData.maxHp
                );
                
                if (updated) {
                    this.mod.log(`[PacketInterceptor] Entity health changed: gameId=${processedData.gameId} hp=${processedData.hp}/${processedData.maxHp}`);
                }
            }
        } catch (error) {
            this.mod.error(`[PacketInterceptor] Error processing health change: ${error.message}`);
        }
    }

    /**
     * Get current player position
     * @returns {Object|null} Current player position or null if not available
     */
    getPlayerPosition() {
        return this.playerPosition ? { ...this.playerPosition } : null;
    }

    /**
     * Get current player rotation
     * @returns {number|null} Current player rotation or null if not available
     */
    getPlayerRotation() {
        return this.playerRotation;
    }

    /**
     * Get current player aim data
     * @returns {Object|null} Current player aim data or null if not available
     */
    getPlayerAimData() {
        return this.playerAimData ? { ...this.playerAimData } : null;
    }

    /**
     * Check if hooks are initialized
     * @returns {boolean} True if hooks are initialized
     */
    isInitialized() {
        return this.hooksInitialized;
    }

    /**
     * Get comprehensive player state for radar output
     * @returns {Object} Complete player state data
     */
    getPlayerState() {
        return {
            position: this.getPlayerPosition(),
            rotation: this.getPlayerRotation(),
            yaw: this.playerAimData?.yaw || null,
            pitch: this.playerAimData?.pitch || null,
            isActive: this.playerPosition !== null
        };
    }

    /**
     * Cleanup resources and unhook packets
     */
    cleanup() {
        this.mod.log('[PacketInterceptor] Cleaning up packet hooks');
        
        // Reset state
        this.playerPosition = null;
        this.playerRotation = null;
        this.playerAimData = null;
        this.hooksInitialized = false;
        
        // Note: TERA Toolbox automatically handles unhooking when mod is unloaded
    }
}

module.exports = PacketInterceptor;