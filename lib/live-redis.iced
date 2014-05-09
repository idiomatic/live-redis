
events = require 'events'
eio = require 'engine.io'
redis = require 'redis'
{parse, quote} = require 'shell-quote'

safe_verbs = ['get', 'bitcount', 'bitpos', 'getbit', 'getrange', 'strlen', 'hexists', 'hget', 'hgetall', 'hkeys', 'hlen', 'hmget', 'hvals', 'llen', 'lindex', 'lrange', 'scard', 'sismember', 'smembers', 'srandmember', 'zcard', 'zcount', 'zlexcount', 'zrange', 'zrangebylex', 'zrangebyscore', 'zrank', 'zrevrange', 'zrevrangebyscore', 'zrevrank', 'zscore']

connect = (options..., cb) ->
    {db_number} = options[0] or {}
    db = redis.createClient()
    if db_number?
        await db.select db_number, defer err
        return cb? err if err?
    cb? null, db

# notify of transition from/to zero listeners
class EdgyEventEmitter extends events.EventEmitter
    constructor: ->
        super()
        @on 'removeListener', (event, listener) =>
            if @listeners(event).length is 0
                @emit 'lastListener', event
        @on 'newListener', (event, listener) =>
            if @listeners(event).length is 0
                @emit 'firstListener', event

# keyspace maps Redis channels to commands dependent upon a key
# subscribe to relevant channels when necessary
class KeyspaceWatcher extends EdgyEventEmitter
    constructor: (options={}) ->
        super()
        {max_channels, db_number} = options
        db_number ?= 0
        @setMaxListeners max_channels if max_channels?
        await connect options, defer err, db_notify
        return if err?
        db_notify.unref()
        @on 'lastListener', (key) ->
            db_notify.unsubscribe "__keyspace@#{db_number}__:#{key}"
        @on 'firstListener', (key) ->
            db_notify.subscribe "__keyspace@#{db_number}__:#{key}"
        db_notify.on 'message', (channel, event) =>
            [_, key] = channel.match /^__keyspace@[0-9]+__:(.*)/
            @emit key, event

# run or cache Redis command output and broadcast/unicast
# get keyspace notifications when necessary
class Command extends EdgyEventEmitter
    constructor: (keyspace, @db, @command, options={}) ->
        super()
        {max_command_watchers} = options
        @setMaxListeners max_command_watchers if max_command_watchers?
        # cached results
        @data = undefined
        [@verb, @key, @args...] = @command
        keyspace.on @key, @keyspace_change
        @on 'lastListener', (event, listener) =>
            keyspace.removeListener @key, @keyspace_change
        @on 'newListener', (event, listener) ->
            await @lazy_run defer err, data
            return if err?
            listener data
    keyspace_change: (event, message) =>
        await @run defer err, data
        return if err?
        @emit 'broadcast', data
    run: (cb) =>
        return cb? 'unsafe' unless @verb in safe_verbs
        await @db[@verb] @key, @args..., defer err, @data
        cb? null, @data
    lazy_run: (cb) =>
        {data} = @
        unless data?
            await @run defer err, data
            return cb err if err?
        # new listener gets free data
        cb? null, data

# embue express with engine.io handler
exports = module.exports = (server, options..., cb) ->
    options = options[0] or {}
    options.max_channels ?= 10000
    options.max_command_watchers ?= 10000
    options.max_socket_commands ?= 10

    io = eio.attach server
    close = ->
        for _, socket of io.clients
            socket.close()
        io.close()
    server.on 'close', close
    process.on 'SIGINT', close

    await connect options, defer err, db
    return if err?
    db.unref()

    keyspace = new KeyspaceWatcher options

    commands = {}
    get_command = (command) ->
        return commands[JSON.stringify command] ?=
            new Command keyspace, db, command, options
                .on 'lastListener', (event, listener) ->
                    return unless event is 'broadcast'
                    delete commands[JSON.stringify command]

    io.on 'connection', (socket) ->
        listeners = {}
        socket.setMaxListeners options.max_socket_commands
        socket.on 'message', (message) ->
            command = parse message
            if command[0].toLowerCase() in safe_verbs
                op = 'once'
            else
                [op, command...] = command
            c = get_command command
            request_id = quote command
            switch op
                when 'ignore'
                    c.removeListener 'broadcast', listeners[request_id]
                when 'watch'
                    listener = (data) ->
                        socket.send JSON.stringify [request_id, data]
                    listeners[request_id] = listener
                    # abusers get booted
                    if socket.listeners('close').length >= options.max_socket_commands
                        return socket.close()
                    c.on 'broadcast', listener
                    socket.once 'close', ->
                        c.removeListener 'broadcast', listener
                when 'once'
                    await c.lazy_run defer err, data
                    return if err?
                    socket.send JSON.stringify [request_id, data]
    cb? null
