Readable = require('stream').Readable
Retry    = require './retry'
merge    = require './merge'
Q        = require 'q'


module.exports = class Proxy extends Readable

    defaults:
        retry:
            min:          0     # minimum delay between retries
            base:         1.2   # exponential base for delay calc
            exp:          33    # max exponent

        max:              5     # max number of retries
        delay:            0     # delay between retries

    # origin is a callback that creates a readable from upstream
    constructor: (@origin, opts) ->
        # make this a readable
        Readable.call this, opts
        # merge in opts from defaults/opts
        merge this, @defaults, opts
        # and create an instance of Retry
        @retryer = new Retry @retry
        # deferred/promise for entire operation
        @def = Q.defer()
        @promise = @def.promise

    _read: ->
        unless @waitFor
            @waitFor = @retryer.try @max, @delay, readFrom(this)
            @waitFor.then =>
                @def.resolve()
            .fail (err) =>
                try
                    @emit 'error', err
                catch err
                    console.log 'No error handler for proxy', err
                @def.reject(err)
            .done()


readFrom = (proxy) ->

    # how far we are into the origin
    pos = 0

    -> Q.Promise (resolve, reject) ->

        # not start new one
        return reject(proxy.abort) if proxy.abort

        # how far this specific readable is into the origin
        cur = 0
        onData = (chunk) ->
            # lingering abort?
            return proxy.emit 'error', proxy.abort if proxy.abort
            if (skip = pos - cur) > 0
                if skip < chunk.length
                    cur += skip
                    chunk = chunk.slice skip
                else
                    cur += chunk.length
                    chunk = null
            more = true
            if chunk?.length
                more = proxy.push chunk
                pos = cur += chunk.length
            unless more
                # what to do?!
                stop()
                Retry.abort "No more pushing?!"

        onError = (err) ->
            stop()
            reject(err)

        onEnd = ->
            proxy.push null
            resolve()

        stop = null

        attach = (src) ->
            # expose on proxy object
            proxy.src = src
            stop = ->
                # and unexpose
                delete proxy.src
                src.removeListener 'data',  onData
                src.removeListener 'error', onError
                src.removeListener 'end',   onEnd

            src.on 'data',  onData
            src.on 'error', onError
            src.on 'end',   onEnd

            # lingering abort?
            proxy.emit 'error', proxy.abort if proxy.abort



        # create a new origin stream
        src = proxy.origin()

        # origin can be a promise for a stream
        if typeof src.then == 'function'
            src.then (src) -> attach(src)
        else
            attach(src)


# Sets an abort value on the given proxy
Proxy.abort = (proxy, message) ->
    proxy.abort = Retry.abort message
    proxy.emit? 'error', proxy.abort
