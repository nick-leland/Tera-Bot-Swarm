/**
 * Entity class representing a tracked entity in the game world
 */
class Entity {
    constructor(gameId, rawData = {}) {
        this.gameId = gameId;
        this.name = rawData.name || 'Unknown';
        this.type = this.determineType(rawData);
        this.position = { x: 0, y: 0, z: 0 };
        this.isFriendly = this.determineFriendlyStatus(rawData.relation);
        this.hp = rawData.hp || null;
        this.maxHp = rawData.maxHp || null;
        this.level = rawData.level || null;
        this.class = rawData.class || null;
        this.lastUpdate = Date.now();
    }

    /**
     * TERA coordinate system conversion factor
     * Based on accurate in-game measurements:
     * 6m actual = 7.39m radar, 10m = 12.72m, 11m = 13.78m, 16m = 19.39m
     * Average correction factor: 0.805
     * Refined conversion: 16.49 units per meter
     */
    static get TERA_UNITS_PER_METER() {
        return 16.49;
    }

    /**
     * Convert TERA coordinate units to real meters
     * @param {number} teraUnits - Distance in TERA coordinate units
     * @returns {number} Distance in meters
     */
    static teraUnitsToMeters(teraUnits) {
        return teraUnits / Entity.TERA_UNITS_PER_METER;
    }

    /**
     * Convert real meters to TERA coordinate units
     * @param {number} meters - Distance in meters
     * @returns {number} Distance in TERA coordinate units
     */
    static metersToTeraUnits(meters) {
        return meters * Entity.TERA_UNITS_PER_METER;
    }

    /**
     * Determine entity type based on raw data
     * @param {Object} rawData - Raw entity data from packet
     * @returns {string} Entity type: 'Player', 'NPC', or 'Monster'
     */
    determineType(rawData) {
        // Check if it's a player character
        if (rawData.playerId || rawData.accountId || rawData.isPlayer) {
            return 'Player';
        }
        
        // Check if it's an NPC (typically has specific NPC flags or templateId patterns)
        if (rawData.templateId) {
            // NPCs typically have templateIds in certain ranges
            // This is game-specific logic that may need adjustment
            const templateId = rawData.templateId;
            
            // Common NPC template ID patterns (these may need adjustment based on actual game data)
            if (templateId >= 1000 && templateId <= 9999) {
                return 'NPC';
            }
            
            // Monsters typically have different template ID ranges
            if (templateId >= 10000) {
                return 'Monster';
            }
        }
        
        // Check for other indicators
        if (rawData.npcId || rawData.isNPC) {
            return 'NPC';
        }
        
        if (rawData.monsterId || rawData.isMonster) {
            return 'Monster';
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
        
        // Relation values interpretation (may need adjustment based on actual game data):
        // 0 = Hostile/Enemy
        // 1 = Neutral
        // 2 = Friendly/Ally
        // 3 = Party member
        // 4 = Guild member
        
        return relation >= 2;
    }

    /**
     * Update entity position
     * @param {Object} newPosition - New position {x, y, z}
     */
    updatePosition(newPosition) {
        if (newPosition && typeof newPosition.x === 'number' && 
            typeof newPosition.y === 'number' && typeof newPosition.z === 'number') {
            this.position = { ...newPosition };
            this.lastUpdate = Date.now();
        }
    }

    /**
     * Update entity health
     * @param {number} hp - Current health points
     * @param {number} maxHp - Maximum health points
     */
    updateHealth(hp, maxHp) {
        if (typeof hp === 'number') {
            this.hp = hp;
        }
        if (typeof maxHp === 'number') {
            this.maxHp = maxHp;
        }
        this.lastUpdate = Date.now();
    }

    /**
     * Calculate distance from player position with optimizations
     * @param {Object} playerPosition - Player position {x, y, z}
     * @returns {number} Distance in meters
     */
    calculateDistanceFrom(playerPosition) {
        if (!playerPosition || !this.position) {
            return Infinity;
        }
        
        const dx = this.position.x - playerPosition.x;
        const dy = this.position.y - playerPosition.y;
        const dz = this.position.z - playerPosition.z;
        
        // Calculate distance in TERA units, then convert to meters
        const teraUnits = Math.sqrt(dx * dx + dy * dy + dz * dz);
        return Entity.teraUnitsToMeters(teraUnits);
    }

    /**
     * Calculate distance from player position in TERA units (for internal calculations)
     * @param {Object} playerPosition - Player position {x, y, z}
     * @returns {number} Distance in TERA coordinate units
     */
    calculateRawDistanceFrom(playerPosition) {
        if (!playerPosition || !this.position) {
            return Infinity;
        }
        
        const dx = this.position.x - playerPosition.x;
        const dy = this.position.y - playerPosition.y;
        const dz = this.position.z - playerPosition.z;
        
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /**
     * Calculate squared distance (faster for comparisons)
     * @param {Object} playerPosition - Player position {x, y, z}
     * @returns {number} Squared distance
     */
    calculateSquaredDistanceFrom(playerPosition) {
        if (!playerPosition || !this.position) {
            return Infinity;
        }
        
        const dx = this.position.x - playerPosition.x;
        const dy = this.position.y - playerPosition.y;
        const dz = this.position.z - playerPosition.z;
        
        return dx * dx + dy * dy + dz * dz;
    }

    /**
     * Check if entity is within specified radius of player (optimized)
     * @param {Object} playerPosition - Player position {x, y, z}
     * @param {number} radius - Radius to check
     * @returns {boolean} True if within radius
     */
    isWithinRadius(playerPosition, radius) {
        // Use squared distance comparison to avoid sqrt calculation
        const radiusSquared = radius * radius;
        return this.calculateSquaredDistanceFrom(playerPosition) <= radiusSquared;
    }

    /**
     * Get entity data formatted for output
     * @param {Object} playerPosition - Player position for distance calculation
     * @returns {Object} Formatted entity data
     */
    toOutputFormat(playerPosition) {
        return {
            gameId: this.gameId,
            name: this.name,
            type: this.type,
            position: { ...this.position },
            distance: playerPosition ? this.calculateDistanceFrom(playerPosition) : null,
            isFriendly: this.isFriendly,
            hp: this.hp,
            maxHp: this.maxHp,
            level: this.level,
            class: this.class
        };
    }
}

module.exports = Entity;