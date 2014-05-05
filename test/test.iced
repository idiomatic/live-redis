
assert = require 'assert'
http = require 'http'
express = require 'express'
live_redis = require '..'
eio = require 'engine.io-client'
redis = require 'redis'

port = 8001
db_number = 15

app = express()
server = http.createServer app
await live_redis server, {db_number}, defer err
assert.ifError err
await server.listen port, defer err
assert.ifError err
console.log "listening on port #{port}"

r = redis.createClient()
await r.select db_number, defer err, status
assert.ifError err
await r.set 'foo', 'bar', defer err, status
assert.ifError err

sockets = []
await
    for i in [1...100]
        socket = new eio.Socket "http://localhost:#{port}/"
            .on 'open', defer()
        sockets.push socket

# hack
await setTimeout defer(), 1000

await
    for socket in sockets
        do (socket, autocb=defer()) ->
            await
                socket.once 'message', defer data
                socket.send 'get foo', defer()
            assert.deepEqual data, JSON.stringify {command:'get foo', data:'bar'}

await
    for socket in sockets
        do (socket, autocb=defer()) ->
            await socket.once 'message', defer data
            assert.deepEqual data, JSON.stringify {command:'get foo', data:'baz'}
    r.set 'foo', 'baz', defer err
assert.ifError err

r.quit()
server.close()
for socket in sockets
    socket.close()
