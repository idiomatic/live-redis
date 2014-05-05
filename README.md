live-redis
==========

Perform non-destructive single-key [Redis](http://redis.io/) commands
over an [Engine.IO](https://github.com/LearnBoost/engine.io) websocket
and in real-time broadcast changes.

Commands are invoked if they are the first actively monitored
invocation of that command.  Commands are re-invoked upon a change
notification from Redis.  The result is cached for subsequent clients.

Requires Redis version 2.8 or later and `CONFIG SET notify-keyspace-events AKE`.

client usage
------------

```html
<script src="/js/engine.io.js"></script>
<script>
    var socket = new eio.Socket();
    socket.on('open', function() {
        socket.send('get thing');
    });
    socket.on('message', function(response) {
        console.log(JSON.parse(response));
    });
    socket.on('close', function() {
        setTimeout(function() {
            socket.open();
        }, 5000);
    });
</script>
```

The command may take the whitespace-separated form:

    "command key arg1 arg2..."

or JSON.stringified:

    '["command", "key", "arg1", "arg2", ...]'


server usage
------------

```javascript
var express = require('express');
require('iced-coffee-script/register');
var live_redis = require('live-redis');
var port = process.env.PORT || 8080;
var app = express();
var server = http.createServer(app);
live_redis(server, {"db_number": 3}, function() {
    server.listen(port, function() {
        console.log("listening on port " + port + ".");
    });
});
```
