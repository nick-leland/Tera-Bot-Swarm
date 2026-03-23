'use strict';

/**
 * DataProcessor class for transforming raw packet data into standardized format
 * Handles entity type determination, friendly/hostile classification, and data processing
 */
class DataProcessor {
    constructor() {
        // Entity type determination constants
        this.NPC_TEMPLATE_ID_MIN = 1000;
        this.NPC_TEMPLATE_ID_MAX = 9999;
        this.MONSTER_TEMPLATE_ID_MIN = 10000;
        
        // Relation constants for friendly/hostile determination
        this.RELATION_HOSTILE = 0;
        this.RELATION_NEUTRAL = 1;
        this.RELATION_FRIENDLY = 2;
        this.RELATION_PARTY = 3;
        this.RELATION_GUILD = 4;
    }

    /**
     * Process player location data from C_PLAYER_LOCATION packet
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed player location data
     */
    processPlayerLocation(rawEvent) {
        if (!rawEvent) {
            return null;
        }

        return {
            position: {
                x: rawEvent.loc?.x || rawEvent.x || 0,
                y: rawEvent.loc?.y || rawEvent.y || 0,
                z: rawEvent.loc?.z || rawEvent.z || 0
            },
            rotation: rawEvent.w || rawEvent.rotation || 0,
            timestamp: Date.now()
        };
    }

    /**
     * Process player aim data from C_USER_AIM packet
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed aim data
     */
    processPlayerAim(rawEvent) {
        if (!rawEvent) {
            return null;
        }

        return {
            yaw: rawEvent.yaw || 0,
            pitch: rawEvent.pitch || 0,
            timestamp: Date.now()
        };
    }

    /**
     * Process entity spawn data from S_SPAWN_USER or S_SPAWN_NPC packets
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed entity spawn data
     */
    processEntitySpawn(rawEvent) {
        if (!rawEvent || !rawEvent.gameId) {
            return null;
        }

        const entityData = {
            gameId: rawEvent.gameId,
            name: rawEvent.name || 'Unknown',
            type: this.determineEntityType(rawEvent),
            position: {
                x: rawEvent.loc?.x || rawEvent.x || 0,
                y: rawEvent.loc?.y || rawEvent.y || 0,
                z: rawEvent.loc?.z || rawEvent.z || 0
            },
            isFriendly: this.determineFriendlyStatus(rawEvent.relation),
            hp: rawEvent.hp || rawEvent.curHp || null,
            maxHp: rawEvent.maxHp || null,
            level: rawEvent.level || null,
            class: rawEvent.class || rawEvent.job || null,
            templateId: rawEvent.templateId || null,
            playerId: rawEvent.playerId || null,
            accountId: rawEvent.accountId || null,
            relation: rawEvent.relation || null
        };

        return entityData;
    }

    /**
     * Process entity movement data from S_USER_LOCATION or S_NPC_LOCATION packets
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed movement data
     */
    processEntityMovement(rawEvent) {
        if (!rawEvent || !rawEvent.gameId) {
            return null;
        }

        return {
            gameId: rawEvent.gameId,
            position: {
                x: rawEvent.loc?.x || rawEvent.x || 0,
                y: rawEvent.loc?.y || rawEvent.y || 0,
                z: rawEvent.loc?.z || rawEvent.z || 0
            },
            rotation: rawEvent.w || rawEvent.rotation || 0,
            timestamp: Date.now()
        };
    }

    /**
     * Process entity health change data from S_CREATURE_CHANGE_HP packet
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed health data
     */
    processEntityHealthChange(rawEvent) {
        if (!rawEvent || !rawEvent.gameId) {
            return null;
        }

        return {
            gameId: rawEvent.gameId,
            hp: rawEvent.curHp || rawEvent.hp || 0,
            maxHp: rawEvent.maxHp || null,
            timestamp: Date.now()
        };
    }

    /**
     * Process entity despawn data from S_DESPAWN_USER or S_DESPAWN_NPC packets
     * @param {Object} rawEvent - Raw packet event data
     * @returns {Object} Processed despawn data
     */
    processEntityDespawn(rawEvent) {
        if (!rawEvent || !rawEvent.gameId) {
            return null;
        }

        return {
            gameId: rawEvent.gameId,
            timestamp: Date.now()
        };
    }

    /**
     * Determine entity type based on packet data
     * @param {Object} rawData - Raw entity data from packet
     * @returns {string} Entity type: 'Player', 'NPC', or 'Monster'
     */
    determineEntityType(rawData) {
        // Check if it's a player character
        if (rawData.playerId || rawData.accountId || rawData.isPlayer) {
            return 'Player';
        }
        
        // Check template ID patterns for NPCs and Monsters
        if (rawData.templateId) {
            const templateId = rawData.templateId;
            
            // NPCs typically have templateIds in specific ranges
            if (templateId >= this.NPC_TEMPLATE_ID_MIN && templateId <= this.NPC_TEMPLATE_ID_MAX) {
                return 'NPC';
            }
            
            // Monsters typically have higher template IDs
            if (templateId >= this.MONSTER_TEMPLATE_ID_MIN) {
                return 'Monster';
            }
        }
        
        // Check for other type indicators
        if (rawData.npcId || rawData.isNPC) {
            return 'NPC';
        }
        
        if (rawData.monsterId || rawData.isMonster) {
            return 'Monster';
        }
        
        // Check if it has player-like properties
        if (rawData.name && rawData.level && rawData.class) {
            return 'Player';
        }
        
        // Default to Monster if we can't determine (safer assumption for targeting)
        return 'Monster';
    }

    /**
     * Determine if entity is friendly based on relation value
     * @param {number} relation - Relation value from packet data
     * @returns {boolean} True if friendly, false if hostile
     */
    determineFriendlyStatus(relation) {
        if (relation === undefined || relation === null) {
            // Default to hostile if relation is unknown (safer for targeting)
            return false;
        }
        
        // Relation values interpretation:
        // 0 = Hostile/Enemy
        // 1 = Neutral (treat as hostile for targeting purposes)
        // 2 = Friendly/Ally
        // 3 = Party member
        // 4 = Guild member
        
        return relation >= this.RELATION_FRIENDLY;
    }

    /**
     * Calculate distance between two positions
     * @param {Object} pos1 - First position {x, y, z}
     * @param {Object} pos2 - Second position {x, y, z}
     * @returns {number} Distance in game units
     */
    calculateDistance(pos1, pos2) {
        if (!pos1 || !pos2) {
            return Infinity;
        }
        
        const dx = pos1.x - pos2.x;
        const dy = pos1.y - pos2.y;
        const dz = pos1.z - pos2.z;
        
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /**
     * Validate position data
     * @param {Object} position - Position object to validate
     * @returns {boolean} True if position is valid
     */
    validatePosition(position) {
        return position && 
               typeof position.x === 'number' && 
               typeof position.y === 'number' && 
               typeof position.z === 'number' &&
               !isNaN(position.x) && 
               !isNaN(position.y) && 
               !isNaN(position.z);
    }

    /**
     * Sanitize entity name for output
     * @param {string} name - Raw entity name
     * @returns {string} Sanitized name
     */
    sanitizeEntityName(name) {
        if (!name || typeof name !== 'string') {
            return 'Unknown';
        }
        
        // Remove any potentially problematic characters
        return name.trim().replace(/[\x00-\x1F\x7F]/g, '').substring(0, 100);
    }

    /**
     * Process and validate health values
     * @param {number} hp - Current health
     * @param {number} maxHp - Maximum health
     * @returns {Object} Processed health data
     */
    processHealthData(hp, maxHp) {
        const processedHp = (typeof hp === 'number' && hp >= 0) ? hp : null;
        const processedMaxHp = (typeof maxHp === 'number' && maxHp > 0) ? maxHp : null;
        
        // If we have current HP but no max HP, estimate max HP
        if (processedHp !== null && processedMaxHp === null) {
            // This is a rough estimation - in practice, max HP might be available elsewhere
            return {
                hp: processedHp,
                maxHp: processedHp, // Assume current HP is max if no max provided
                healthPercentage: 100
            };
        }
        
        // Calculate health percentage if both values are available
        let healthPercentage = null;
        if (processedHp !== null && processedMaxHp !== null && processedMaxHp > 0) {
            healthPercentage = Math.round((processedHp / processedMaxHp) * 100);
        }
        
        return {
            hp: processedHp,
            maxHp: processedMaxHp,
            healthPercentage: healthPercentage
        };
    }

    /**
     * Create a standardized entity update object
     * @param {Object} rawData - Raw packet data
     * @param {string} updateType - Type of update ('spawn', 'move', 'health', 'despawn')
     * @returns {Object} Standardized entity update
     */
    createEntityUpdate(rawData, updateType) {
        if (!rawData || !rawData.gameId) {
            return null;
        }

        const baseUpdate = {
            gameId: rawData.gameId,
            updateType: updateType,
            timestamp: Date.now()
        };

        switch (updateType) {
            case 'spawn':
                return {
                    ...baseUpdate,
                    ...this.processEntitySpawn(rawData)
                };
                
            case 'move':
                return {
                    ...baseUpdate,
                    ...this.processEntityMovement(rawData)
                };
                
            case 'health':
                return {
                    ...baseUpdate,
                    ...this.processEntityHealthChange(rawData)
                };
                
            case 'despawn':
                return {
                    ...baseUpdate,
                    ...this.processEntityDespawn(rawData)
                };
                
            default:
                return baseUpdate;
        }
    }
}

module.exports = DataProcessor;