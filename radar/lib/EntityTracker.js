const Entity = require('./Entity');

/**
 * EntityTracker class for managing all tracked entities with spatial filtering
 * Optimized for high-performance entity lookup and distance calculations
 */
class EntityTracker {
    constructor(radarRadius = 50) {
        this.entities = new Map(); // gameId -> Entity
        this.playerPosition = null;
        this.radarRadius = radarRadius; // Radius in meters
        this.radarRadiusTeraUnits = Entity.metersToTeraUnits(radarRadius); // Convert to TERA units for filtering
        
        console.log(`[EntityTracker] Radar radius set to ${radarRadius}m (${this.radarRadiusTeraUnits.toFixed(2)} TERA units)`);
        this.lastCleanup = Date.now();
        this.cleanupInterval = 30000; // 30 seconds
        
        // Performance optimization: spatial indexing
        this.spatialGrid = new Map(); // gridKey -> Set<gameId>
        this.gridSize = Math.max(this.radarRadiusTeraUnits / 2, Entity.metersToTeraUnits(25)); // Grid cell size for spatial indexing in TERA units
        
        // Performance monitoring
        this.performanceMetrics = {
            entityUpdates: 0,
            distanceCalculations: 0,
            spatialQueries: 0,
            cleanupOperations: 0,
            lastUpdateTime: 0,
            averageUpdateTime: 0,
            maxUpdateTime: 0
        };
        
        // Distance calculation cache
        this.distanceCache = new Map(); // `${gameId}_${playerPosHash}` -> distance
        this.lastPlayerPosHash = null;
        
        // Memory management
        this.maxEntities = 1000; // Prevent memory leaks
        this.staleEntityThreshold = 60000; // 60 seconds
    }

    /**
     * Add or update an entity with spatial indexing optimization
     * @param {Object} entityData - Raw entity data from packet
     * @returns {Entity} The created or updated entity
     */
    addEntity(entityData) {
        const startTime = Date.now();
        const gameId = entityData.gameId;
        
        if (!gameId && gameId !== 0) {
            console.warn('EntityTracker: Cannot add entity without gameId');
            return null;
        }

        // Check entity limit to prevent memory leaks
        if (this.entities.size >= this.maxEntities && !this.entities.has(gameId)) {
            this.performEmergencyCleanup();
        }

        let entity = this.entities.get(gameId);
        let oldPosition = null;
        
        if (entity) {
            // Store old position for spatial index update
            oldPosition = entity.position ? { ...entity.position } : null;
            
            // Update existing entity
            if (entityData.position) {
                entity.updatePosition(entityData.position);
                this.updateSpatialIndex(gameId, oldPosition, entityData.position);
            }
            if (entityData.hp !== undefined || entityData.maxHp !== undefined) {
                entity.updateHealth(entityData.hp, entityData.maxHp);
            }
            // Update other properties if provided
            if (entityData.name) entity.name = entityData.name;
            if (entityData.level) entity.level = entityData.level;
            if (entityData.class) entity.class = entityData.class;
        } else {
            // Create new entity
            entity = new Entity(gameId, entityData);
            if (entityData.position) {
                entity.updatePosition(entityData.position);
                this.addToSpatialIndex(gameId, entityData.position);
            }
            this.entities.set(gameId, entity);
        }

        // Clear distance cache for this entity
        this.invalidateDistanceCache(gameId);
        
        // Update performance metrics
        this.performanceMetrics.entityUpdates++;
        const updateTime = Date.now() - startTime;
        this.updatePerformanceMetrics(updateTime);

        return entity;
    }

    /**
     * Remove an entity by gameId with spatial index cleanup
     * @param {number} gameId - Game ID of entity to remove
     * @returns {boolean} True if entity was removed
     */
    removeEntity(gameId) {
        const entity = this.entities.get(gameId);
        if (entity && entity.position) {
            this.removeFromSpatialIndex(gameId, entity.position);
        }
        
        // Clear distance cache for this entity
        this.invalidateDistanceCache(gameId);
        
        return this.entities.delete(gameId);
    }

    /**
     * Update entity position with spatial index optimization
     * @param {number} gameId - Game ID of entity
     * @param {Object} position - New position {x, y, z}
     * @returns {boolean} True if entity was found and updated
     */
    updateEntityPosition(gameId, position) {
        const entity = this.entities.get(gameId);
        if (entity) {
            const oldPosition = entity.position ? { ...entity.position } : null;
            entity.updatePosition(position);
            this.updateSpatialIndex(gameId, oldPosition, position);
            this.invalidateDistanceCache(gameId);
            return true;
        }
        return false;
    }

    /**
     * Update entity health
     * @param {number} gameId - Game ID of entity
     * @param {number} hp - Current health points
     * @param {number} maxHp - Maximum health points (optional)
     * @returns {boolean} True if entity was found and updated
     */
    updateEntityHealth(gameId, hp, maxHp) {
        const entity = this.entities.get(gameId);
        if (entity) {
            entity.updateHealth(hp, maxHp);
            return true;
        }
        return false;
    }

    /**
     * Set player position for distance calculations with cache invalidation
     * @param {Object} position - Player position {x, y, z}
     */
    setPlayerPosition(position) {
        if (position && typeof position.x === 'number' && 
            typeof position.y === 'number' && typeof position.z === 'number') {
            
            const newPosHash = this.hashPosition(position);
            
            // Only update if position actually changed
            if (this.lastPlayerPosHash !== newPosHash) {
                this.playerPosition = { ...position };
                this.lastPlayerPosHash = newPosHash;
                
                // Clear distance cache when player moves
                this.distanceCache.clear();
            }
        }
    }

    /**
     * Get all entities within radar radius using optimized spatial queries
     * @returns {Array<Entity>} Array of entities within radius
     */
    getEntitiesInRadius() {
        const startTime = Date.now();
        
        if (!this.playerPosition) {
            return [];
        }

        this.performanceMetrics.spatialQueries++;
        
        // Use spatial indexing for faster queries
        const candidateEntities = this.getSpatialCandidates(this.playerPosition, this.radarRadiusTeraUnits);
        const entitiesInRadius = [];
        
        for (const gameId of candidateEntities) {
            const entity = this.entities.get(gameId);
            if (entity && this.isEntityInRadius(entity, this.playerPosition, this.radarRadiusTeraUnits)) {
                entitiesInRadius.push(entity);
            }
        }

        // Sort by distance (closest first) using cached distances
        entitiesInRadius.sort((a, b) => {
            const distA = this.getCachedDistance(a.gameId, this.playerPosition);
            const distB = this.getCachedDistance(b.gameId, this.playerPosition);
            return distA - distB;
        });

        // Update performance metrics
        const queryTime = Date.now() - startTime;
        this.updatePerformanceMetrics(queryTime);

        return entitiesInRadius;
    }

    /**
     * Get entities filtered by type and within radius
     * @param {string|Array<string>} types - Entity type(s) to include
     * @returns {Array<Entity>} Filtered entities
     */
    getEntitiesByType(types) {
        const typeArray = Array.isArray(types) ? types : [types];
        const entitiesInRadius = this.getEntitiesInRadius();
        
        return entitiesInRadius.filter(entity => typeArray.includes(entity.type));
    }

    /**
     * Get entities filtered by friendly status and within radius
     * @param {boolean} isFriendly - True for friendly, false for hostile
     * @returns {Array<Entity>} Filtered entities
     */
    getEntitiesByFriendlyStatus(isFriendly) {
        const entitiesInRadius = this.getEntitiesInRadius();
        
        return entitiesInRadius.filter(entity => entity.isFriendly === isFriendly);
    }

    /**
     * Get entity by gameId
     * @param {number} gameId - Game ID to search for
     * @returns {Entity|null} Entity if found, null otherwise
     */
    getEntity(gameId) {
        return this.entities.get(gameId) || null;
    }

    /**
     * Get all entities (regardless of radius)
     * @returns {Array<Entity>} All tracked entities
     */
    getAllEntities() {
        return Array.from(this.entities.values());
    }

    /**
     * Get radar snapshot for output
     * @param {Object} playerState - Player state from PacketInterceptor (optional)
     * @returns {Object} Complete radar data snapshot
     */
    getRadarSnapshot(playerState = null) {
        const entitiesInRadius = this.getEntitiesInRadius();
        
        // Use provided player state or fall back to internal position data
        let playerData = {
            position: this.playerPosition ? { ...this.playerPosition } : null,
            rotation: null,
            yaw: null,
            pitch: null,
            isActive: this.playerPosition !== null
        };

        // If player state is provided, use it to enhance the player data
        if (playerState) {
            playerData = {
                position: playerState.position ? { ...playerState.position } : playerData.position,
                rotation: playerState.rotation !== undefined ? playerState.rotation : playerData.rotation,
                yaw: playerState.yaw !== undefined ? playerState.yaw : playerData.yaw,
                pitch: playerState.pitch !== undefined ? playerState.pitch : playerData.pitch,
                isActive: playerState.isActive !== undefined ? playerState.isActive : playerData.isActive
            };
        }
        
        return {
            timestamp: new Date().toISOString(),
            player: playerData,
            entities: entitiesInRadius.map(entity => entity.toOutputFormat(this.playerPosition)),
            metadata: {
                entitiesInRadius: entitiesInRadius.length,
                radarRadius: this.radarRadius,
                totalEntitiesTracked: this.entities.size
            }
        };
    }

    /**
     * Update radar radius
     * @param {number} radius - New radar radius in meters
     */
    setRadarRadius(radius) {
        if (typeof radius === 'number' && radius > 0) {
            this.radarRadius = radius;
            this.radarRadiusTeraUnits = Entity.metersToTeraUnits(radius);
            this.gridSize = Math.max(this.radarRadiusTeraUnits / 2, Entity.metersToTeraUnits(25)); // Update grid size
            console.log(`[EntityTracker] Radar radius updated to ${radius}m (${this.radarRadiusTeraUnits.toFixed(2)} TERA units)`);
        }
    }

    /**
     * Calculate distance between two positions
     * @param {Object} pos1 - First position {x, y, z}
     * @param {Object} pos2 - Second position {x, y, z}
     * @returns {number} Distance between positions
     */
    static calculateDistance(pos1, pos2) {
        if (!pos1 || !pos2) {
            return Infinity;
        }
        
        const dx = pos1.x - pos2.x;
        const dy = pos1.y - pos2.y;
        const dz = pos1.z - pos2.z;
        
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /**
     * Clean up stale entities (entities that haven't been updated recently)
     * @param {number} maxAge - Maximum age in milliseconds (default: 60 seconds)
     */
    cleanupStaleEntities(maxAge = 60000) {
        const now = Date.now();
        const staleEntities = [];
        
        for (const [gameId, entity] of this.entities) {
            if (now - entity.lastUpdate > maxAge) {
                staleEntities.push(gameId);
            }
        }
        
        staleEntities.forEach(gameId => {
            this.entities.delete(gameId);
        });
        
        if (staleEntities.length > 0) {
            console.log(`EntityTracker: Cleaned up ${staleEntities.length} stale entities`);
        }
        
        this.lastCleanup = now;
    }

    /**
     * Perform periodic maintenance
     */
    performMaintenance() {
        const now = Date.now();
        
        // Run cleanup if enough time has passed
        if (now - this.lastCleanup > this.cleanupInterval) {
            this.cleanupStaleEntities();
        }
    }

    /**
     * Clear all entities
     */
    clear() {
        this.entities.clear();
        this.playerPosition = null;
    }

    /**
     * Get statistics about tracked entities including performance metrics
     * @returns {Object} Statistics object
     */
    getStats() {
        const entitiesInRadius = this.getEntitiesInRadius();
        const typeStats = {};
        
        // Count entities by type
        for (const entity of this.entities.values()) {
            typeStats[entity.type] = (typeStats[entity.type] || 0) + 1;
        }
        
        return {
            totalEntities: this.entities.size,
            entitiesInRadius: entitiesInRadius.length,
            radarRadius: this.radarRadius,
            playerPosition: this.playerPosition,
            typeBreakdown: typeStats,
            hasPlayerPosition: this.playerPosition !== null,
            performance: {
                ...this.performanceMetrics,
                distanceCacheSize: this.distanceCache.size,
                spatialGridCells: this.spatialGrid.size,
                memoryUsage: this.getMemoryUsage()
            }
        };
    }

    // ==================== SPATIAL INDEXING METHODS ====================

    /**
     * Generate grid key for spatial indexing
     * @param {Object} position - Position {x, y, z}
     * @returns {string} Grid key
     */
    getGridKey(position) {
        const gridX = Math.floor(position.x / this.gridSize);
        const gridY = Math.floor(position.y / this.gridSize);
        const gridZ = Math.floor(position.z / this.gridSize);
        return `${gridX},${gridY},${gridZ}`;
    }

    /**
     * Add entity to spatial index
     * @param {number} gameId - Entity game ID
     * @param {Object} position - Entity position
     */
    addToSpatialIndex(gameId, position) {
        const gridKey = this.getGridKey(position);
        if (!this.spatialGrid.has(gridKey)) {
            this.spatialGrid.set(gridKey, new Set());
        }
        this.spatialGrid.get(gridKey).add(gameId);
    }

    /**
     * Remove entity from spatial index
     * @param {number} gameId - Entity game ID
     * @param {Object} position - Entity position
     */
    removeFromSpatialIndex(gameId, position) {
        const gridKey = this.getGridKey(position);
        const gridCell = this.spatialGrid.get(gridKey);
        if (gridCell) {
            gridCell.delete(gameId);
            if (gridCell.size === 0) {
                this.spatialGrid.delete(gridKey);
            }
        }
    }

    /**
     * Update entity in spatial index
     * @param {number} gameId - Entity game ID
     * @param {Object} oldPosition - Old position
     * @param {Object} newPosition - New position
     */
    updateSpatialIndex(gameId, oldPosition, newPosition) {
        if (oldPosition) {
            this.removeFromSpatialIndex(gameId, oldPosition);
        }
        if (newPosition) {
            this.addToSpatialIndex(gameId, newPosition);
        }
    }

    /**
     * Get candidate entities from spatial grid
     * @param {Object} center - Center position
     * @param {number} radius - Search radius
     * @returns {Set<number>} Set of candidate entity IDs
     */
    getSpatialCandidates(center, radius) {
        const candidates = new Set();
        const gridRadius = Math.ceil(radius / this.gridSize);
        const centerGridX = Math.floor(center.x / this.gridSize);
        const centerGridY = Math.floor(center.y / this.gridSize);
        const centerGridZ = Math.floor(center.z / this.gridSize);

        // Check surrounding grid cells
        for (let dx = -gridRadius; dx <= gridRadius; dx++) {
            for (let dy = -gridRadius; dy <= gridRadius; dy++) {
                for (let dz = -gridRadius; dz <= gridRadius; dz++) {
                    const gridKey = `${centerGridX + dx},${centerGridY + dy},${centerGridZ + dz}`;
                    const gridCell = this.spatialGrid.get(gridKey);
                    if (gridCell) {
                        for (const gameId of gridCell) {
                            candidates.add(gameId);
                        }
                    }
                }
            }
        }

        return candidates;
    }

    // ==================== DISTANCE CACHING METHODS ====================

    /**
     * Generate position hash for caching
     * @param {Object} position - Position {x, y, z}
     * @returns {string} Position hash
     */
    hashPosition(position) {
        // Round to reduce cache misses from tiny movements
        const x = Math.round(position.x * 10) / 10;
        const y = Math.round(position.y * 10) / 10;
        const z = Math.round(position.z * 10) / 10;
        return `${x},${y},${z}`;
    }

    /**
     * Get cached distance or calculate and cache it (in meters)
     * @param {number} gameId - Entity game ID
     * @param {Object} playerPosition - Player position
     * @returns {number} Distance in meters
     */
    getCachedDistance(gameId, playerPosition) {
        const entity = this.entities.get(gameId);
        if (!entity || !entity.position) {
            return Infinity;
        }

        const cacheKey = `${gameId}_${this.lastPlayerPosHash}`;
        let distance = this.distanceCache.get(cacheKey);
        
        if (distance === undefined) {
            distance = entity.calculateDistanceFrom(playerPosition);
            this.distanceCache.set(cacheKey, distance);
            this.performanceMetrics.distanceCalculations++;
        }
        
        return distance;
    }

    /**
     * Get cached raw distance or calculate and cache it (in TERA units)
     * @param {number} gameId - Entity game ID
     * @param {Object} playerPosition - Player position
     * @returns {number} Distance in TERA coordinate units
     */
    getCachedRawDistance(gameId, playerPosition) {
        const entity = this.entities.get(gameId);
        if (!entity || !entity.position) {
            return Infinity;
        }

        const cacheKey = `raw_${gameId}_${this.lastPlayerPosHash}`;
        let distance = this.distanceCache.get(cacheKey);
        
        if (distance === undefined) {
            distance = entity.calculateRawDistanceFrom(playerPosition);
            this.distanceCache.set(cacheKey, distance);
            this.performanceMetrics.distanceCalculations++;
        }
        
        return distance;
    }

    /**
     * Check if entity is in radius using cached distance
     * @param {Entity} entity - Entity to check
     * @param {Object} playerPosition - Player position
     * @param {number} radiusTeraUnits - Radius to check in TERA units
     * @returns {boolean} True if in radius
     */
    isEntityInRadius(entity, playerPosition, radiusTeraUnits) {
        const distanceTeraUnits = this.getCachedRawDistance(entity.gameId, playerPosition);
        return distanceTeraUnits <= radiusTeraUnits;
    }

    /**
     * Invalidate distance cache for specific entity
     * @param {number} gameId - Entity game ID
     */
    invalidateDistanceCache(gameId) {
        // Remove all cache entries for this entity
        for (const [key] of this.distanceCache) {
            if (key.startsWith(`${gameId}_`)) {
                this.distanceCache.delete(key);
            }
        }
    }

    // ==================== PERFORMANCE MONITORING METHODS ====================

    /**
     * Update performance metrics
     * @param {number} operationTime - Time taken for operation in ms
     */
    updatePerformanceMetrics(operationTime) {
        this.performanceMetrics.lastUpdateTime = operationTime;
        
        // Update average (simple moving average)
        if (this.performanceMetrics.averageUpdateTime === 0) {
            this.performanceMetrics.averageUpdateTime = operationTime;
        } else {
            this.performanceMetrics.averageUpdateTime = 
                (this.performanceMetrics.averageUpdateTime * 0.9) + (operationTime * 0.1);
        }
        
        // Update max
        if (operationTime > this.performanceMetrics.maxUpdateTime) {
            this.performanceMetrics.maxUpdateTime = operationTime;
        }
    }

    /**
     * Get memory usage estimation
     * @returns {Object} Memory usage info
     */
    getMemoryUsage() {
        const entityMemory = this.entities.size * 200; // Rough estimate per entity
        const spatialMemory = this.spatialGrid.size * 50; // Rough estimate per grid cell
        const cacheMemory = this.distanceCache.size * 20; // Rough estimate per cache entry
        
        return {
            totalEstimatedBytes: entityMemory + spatialMemory + cacheMemory,
            entities: entityMemory,
            spatialIndex: spatialMemory,
            distanceCache: cacheMemory
        };
    }

    /**
     * Check if update frequency is within compliance
     * @param {number} targetInterval - Target update interval in ms
     * @returns {boolean} True if compliant
     */
    isUpdateFrequencyCompliant(targetInterval = 50) {
        return this.performanceMetrics.averageUpdateTime <= targetInterval;
    }

    // ==================== MEMORY MANAGEMENT METHODS ====================

    /**
     * Perform emergency cleanup when entity limit is reached
     */
    performEmergencyCleanup() {
        console.warn(`EntityTracker: Entity limit (${this.maxEntities}) reached, performing emergency cleanup`);
        
        // Remove oldest entities first
        const entities = Array.from(this.entities.entries());
        entities.sort((a, b) => a[1].lastUpdate - b[1].lastUpdate);
        
        const entitiesToRemove = Math.floor(this.maxEntities * 0.1); // Remove 10%
        for (let i = 0; i < entitiesToRemove && i < entities.length; i++) {
            const [gameId] = entities[i];
            this.removeEntity(gameId);
        }
        
        this.performanceMetrics.cleanupOperations++;
        console.log(`EntityTracker: Emergency cleanup removed ${entitiesToRemove} entities`);
    }

    /**
     * Clean up stale entities with improved efficiency
     * @param {number} maxAge - Maximum age in milliseconds (default: 60 seconds)
     */
    cleanupStaleEntities(maxAge = 60000) {
        const startTime = Date.now();
        const now = Date.now();
        const staleEntities = [];
        
        for (const [gameId, entity] of this.entities) {
            if (now - entity.lastUpdate > maxAge) {
                staleEntities.push(gameId);
            }
        }
        
        staleEntities.forEach(gameId => {
            this.removeEntity(gameId);
        });
        
        // Clean up distance cache periodically
        if (this.distanceCache.size > 1000) {
            this.distanceCache.clear();
        }
        
        // Clean up empty spatial grid cells
        for (const [gridKey, gridCell] of this.spatialGrid) {
            if (gridCell.size === 0) {
                this.spatialGrid.delete(gridKey);
            }
        }
        
        if (staleEntities.length > 0) {
            console.log(`EntityTracker: Cleaned up ${staleEntities.length} stale entities`);
        }
        
        this.lastCleanup = now;
        this.performanceMetrics.cleanupOperations++;
        
        const cleanupTime = Date.now() - startTime;
        console.log(`EntityTracker: Cleanup completed in ${cleanupTime.toFixed(2)}ms`);
    }
}

module.exports = EntityTracker;