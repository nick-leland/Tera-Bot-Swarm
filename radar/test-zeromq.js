#!/usr/bin/env node

console.log('Testing ZeroMQ installation...');

try {
    const zmq = require('zeromq');
    console.log('ZeroMQ loaded successfully');
    console.log('ZeroMQ version:', zmq.version);
    
    // Test creating a socket
    const publisher = new zmq.Publisher();
    console.log('Publisher socket created successfully');
    
    // Test binding (this will fail if port is in use, but that's expected)
    publisher.bind('tcp://127.0.0.1:3001').then(() => {
        console.log('Publisher bound successfully');
        publisher.close();
        console.log('ZeroMQ is working correctly!');
        process.exit(0);
    }).catch((error) => {
        if (error.code === 'EADDRINUSE') {
            console.log('Publisher binding test passed (port in use is expected)');
            publisher.close();
            console.log('ZeroMQ is working correctly!');
            process.exit(0);
        } else {
            throw error;
        }
    });
    
} catch (error) {
    console.error('ZeroMQ test failed:', error.message);
    console.error('\nThis usually means ZeroMQ needs to be rebuilt for Electron.');
    console.error('   Run: node build.js');
    process.exit(1);
}
