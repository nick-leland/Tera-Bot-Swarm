'use strict';

const DataProcessor = require('./lib/DataProcessor');
const EntityTracker = require('./lib/EntityTracker');
const PacketInterceptor = require('./lib/PacketInterceptor');

// Try to load ZeroMQ with fallback
let zmq;
try {
    zmq = require("zeromq");
} catch (error) {
    console.error('[TeraRadarMod] ZeroMQ failed to load:', error.message);
    console.error('[TeraRadarMod] Please run: node build.js to rebuild ZeroMQ for Electron');
    throw new Error('ZeroMQ not available. Run "node build.js" to install properly.');
}

// Constants
const radar_interval = 1500;
const radar_radius = 1000;

// Helper to safely stringify objects containing BigInt values
const safeStringify = (payload) => {
    return JSON.stringify(payload, (_, value) => typeof value === 'bigint' ? value.toString() : value);
};

async function create_socket(mod) {
    try {
        const sock = new zmq.Publisher()
        await sock.bind("tcp://127.0.0.1:3000")
        mod.log("Publisher bound to port 3000")
        return sock
    } catch (error) {
        mod.error(`[TeraRadarMod] Error creating socket: ${error.message}`);
        return null
    }
}

async function send_to_server(mod, data, sock) {
    try {
        if (!sock) {
            throw new Error('Socket is not initialized');
        }

        const serializedPayload = safeStringify(data);
        mod.log("Sending data to server")
        await sock.send([serializedPayload])
    } catch (error) {
        mod.error(`[TeraRadarMod] Error sending data to server: ${error.message}`);
    }
}


module.exports = function TeraRadarModMain(mod) {
    mod.log('[TeraRadarMod] Creating DataProcessor...');
    // Initialize DataProcessor
    const dataProcessor = new DataProcessor();

    mod.log('[TeraRadarMod] Creating EntityTracker...');
    // Initialize EntityTracker with radar radius from config
    const entityTracker = new EntityTracker(radar_radius);

    mod.log('[TeraRadarMod] Creating PacketInterceptor...');
    // Initialize PacketInterceptor with dependencies
    const packetInterceptor = new PacketInterceptor(
        mod,
        dataProcessor,
        entityTracker
    );

    mod.game.on('enter_game', async () => {
        mod.log('[TeraRadarMod] Entered game - initializing systems');

        const sock = await create_socket(mod);

        // Initialize portion to begin tracing those packages
        try {
            packetInterceptor.initializeHooks();
            mod.log('[TeraRadarMod] Packet interceptor hooks initialized successfully');
        } catch (error) {
            mod.error(`[TeraRadarMod] Error initializing packet interceptor: ${error.message}`);
        }

        // Set up periodic radar data sending
        const radarInterval = setInterval(async () => {
            try {
                // Combine all the data into a single object 
                // (Player position and other entities)
                const { position: character_position, rotation, yaw, pitch, isActive } = packetInterceptor.getPlayerState();
                const entities = entityTracker.getEntitiesInRadius();
                const entity_output = {
                    "player": {
                        "position": character_position,
                        "rotation": rotation,
                        "yaw": yaw,
                        "pitch": pitch,
                        "isActive": isActive
                    },
                    "entities": entities
                };

                // Send the data to the server
                await send_to_server(mod, entity_output, sock);
            } catch (error) {
                mod.error(`[TeraRadarMod] Error in radar interval: ${error.message}`);
            }
        }, radar_interval);

        // TODO: Add some sort of in game call to view the last sent data

        // Clean up interval when leaving game
        mod.game.on('leave_game', () => {
            if (radarInterval) {
                clearInterval(radarInterval);
                mod.log('[TeraRadarMod] Radar interval cleared');
            }
        });

    });

    
};
