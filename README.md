live-redis
==========

perform non-destructive single-key Redis commands over a websocket and
broadcast changes.

requires Redis >= 2.8 and `CONFIG SET notify-keyspace-events AKE`.


client usage
------------

    <script src="/js/engine.io.js"></script>
    <script>
        var socket = new eio.Socket();
        socket.on('open', function() {
            socket.send('get thing');
        });
        socket.on('message', function(response) {
            response = JSON.parse(response);
            console.log(response);
        });
        socket.on('close', function() {
            setTimeout(function() {
                socket.open();
            }, 5000);
        });
