
'use strict';

const TeraRadarMod = require('./lib/TeraRadarMod');

/**
 * Tera Radar Mod - Main Entry Point
 * A high-performance modification for Tera Toolbox that provides real-time entity tracking
 * optimized for external Python consumption and aimbot integration.
 * 
 * This is the clean, optimized entry point that uses the new modular architecture.
 * All legacy code has been migrated to the appropriate classes.
 */
module.exports = function TeraRadarModMain(mod) {
    mod.log('[TeraRadarMod] Module entry point called');
    
    try {
        mod.log('[TeraRadarMod] Creating TeraRadarMod instance...');
        
        // Create and initialize the main mod instance first
        const radarMod = new TeraRadarMod(mod);
        
        mod.log('[TeraRadarMod] TeraRadarMod instance created successfully');

        // Add debug logging for command registration
        mod.log('[TeraRadarMod] Attempting to register commands...');

        // Commands will be registered after entering game in TeraRadarMod.onEnterGame()
        mod.log('[TeraRadarMod] Initialization complete, commands will be registered after entering game');

        // Store reference for cleanup
        mod._radarModInstance = radarMod;

        // Enhanced mod unload/reload handling with better error recovery
        const cleanup = (reason = 'unknown') => {
            if (mod._radarModInstance) {
                try {
                    mod.log(`[TeraRadarMod] Starting cleanup due to: ${reason}`);
                    mod._radarModInstance.cleanup();
                    mod._radarModInstance = null;
                    mod.log(`[TeraRadarMod] Cleanup completed successfully for: ${reason}`);
                } catch (error) {
                    mod.error(`[TeraRadarMod] Cleanup error during ${reason}: ${error.message}`);
                    // Force clear the instance even if cleanup failed
                    mod._radarModInstance = null;
                }
            }
        };

        // Register cleanup handlers for various shutdown scenarios
        process.on('exit', () => cleanup('process exit'));
        process.on('SIGINT', () => cleanup('SIGINT'));
        process.on('SIGTERM', () => cleanup('SIGTERM'));
        process.on('uncaughtException', (error) => {
            mod.error(`[TeraRadarMod] Uncaught exception: ${error.message}`);
            cleanup('uncaught exception');
        });

        // Handle mod-specific cleanup and reload scenarios
        if (mod.destructor) {
            mod.destructor(() => cleanup('mod destructor'));
        }

        // Handle TERA Toolbox specific reload events if available
        if (mod.hook && typeof mod.hook === 'function') {
            try {
                // Hook into mod reload events if supported by this version of TERA Toolbox
                mod.hook('*', 'event', () => {
                    // This is a generic hook that might catch reload events
                    // We'll use it to detect when the mod might be reloading
                });
            } catch (error) {
                // Ignore hook errors - not all TERA Toolbox versions support this
                mod.log(`[TeraRadarMod] Hook registration note: ${error.message}`);
            }
        }

        // Store cleanup function reference for manual cleanup if needed
        mod._cleanupFunction = cleanup;

        mod.log('[TeraRadarMod] Successfully initialized with optimized architecture');

    } catch (error) {
        mod.error(`[TeraRadarMod] Initialization failed: ${error.message}`);
        mod.error(`[TeraRadarMod] Stack trace: ${error.stack}`);
    }
};