merge = require './merge'
Q     = require 'q'

# Error that indicates we want to abort
class AbortError extends Error then constructor: (@message) -> super

module.exports = class Retry

    min:          0
    base:         1.2
    exp:          33
    defaultMax:   5
    defaultDelay: 1000

    constructor: (options) ->
        merge this, options

    delay: (attempt, delay) ->
        @min + Math.floor(delay * Math.pow(@base, Math.min(@exp, attempt)) +
            delay / 2 * Math.random())

    try: (max, delay, f) ->
        _this = this
        if arguments.length == 2
            [max, f] = arguments
            delay = @defaultDelay
        else if arguments.length == 1
            [f] = arguments
            max = @defaultMax
            delay = @defaultDelay
        lastErr = null
        Q.Promise (resolve, reject) ->
            do tryAgain = (attempt = 0) ->
                if attempt >= max
                    reject lastErr
                    return
                p = f()
                firstError = false
                onErr = (err) ->
                    # ignore consecutive errors
                    return if firstError
                    firstError = true
                    lastErr = err
                    if err instanceof AbortError
                        reject err
                    else if (delay = _this.delay attempt, delay) >= 0
                        setTimeout (-> tryAgain attempt + 1), delay
                    else
                        reject new Error("Aborted with #{delay}")
                    null
                # treat as a promise which ends immediatelly
                p.then ((v) -> resolve v), onErr
            null

# helper function to abort retries
Retry.abort = (reason) -> new AbortError(reason)
