{Readable, Writable} = require('stream')
Proxy = require '../src/proxy'
Q     = require 'q'

count = 0

class TestReadable extends Readable

    constructor: (@buf, @chunksize, @errorpos = 99999, opts) ->
        Readable.call this, opts
        count++
        @def = Q.defer()
        @promise = @def.promise

    _read: ->
        return if @started
        @started = true
        setTimeout (=> @feedNext 0, @errorpos), 0

    feedNext: (from, errorpos) =>
        to = Math.min @buf.length, from + @chunksize, errorpos
        @push @buf.slice from, to
        if to == errorpos
            @emit 'error', new Error("Deliberate fail")
        else if to < @buf.length
            setTimeout (=> @feedNext(to, errorpos)), 0
        else
            @push null
            @def.resolve()



class TestWritable extends Writable

    constructor: (opts) ->
        Writable.call this, opts
        @buf = new Buffer('')
        def = Q.defer()
        @promise = def.promise
        @on 'finish', -> def.resolve()
        @on 'error', (err) ->
            def.reject(err)

    _write: (chunk, enc, cb) ->
        @buf = Buffer.concat [@buf, chunk]
        cb()



describe 'proxy', ->

    inp = out = test = proxy = null
    beforeEach ->
        count = 0
        test = new Buffer 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVW0123456789'
        out = new TestWritable()


    it 'proxies a readable', ->
        proxy = new Proxy (-> inp = new TestReadable test, 4)
        proxy.pipe out
        out.promise.then ->
            assert.isNotNull inp
            eql out.buf, test
            eql count, 1


    it 'retries if one error is encountered and resumes', ->
        errpos = [7]
        proxy = new Proxy (-> inp = new TestReadable test, 4, errpos.shift())
        proxy.pipe out
        out.promise.then ->
            assert.isNotNull inp
            eql out.buf, test
            eql count, 2


    it 'retries if four errors are encountered and resumes', ->
        errpos = [7, 10, 22, 44]
        proxy = new Proxy (-> inp = new TestReadable test, 4, errpos.shift())
        proxy.pipe out
        out.promise.then ->
            assert.isNotNull inp
            eql out.buf, test
            eql count, 5


    it 'retries ok if error is before previous successful position', ->
        errpos = [10, 4]
        proxy = new Proxy (-> inp = new TestReadable test, 4, errpos.shift())
        proxy.pipe out
        out.promise.then ->
            assert.isNotNull inp
            eql out.buf, test
            eql count, 3


    it 'with 5 errors makes proxy emit error', (done) ->
        errpos = [1, 2, 3, 4, 5]
        proxy = new Proxy (-> inp = new TestReadable test, 4, errpos.shift())
        proxy.on 'error', (err) ->
            eql err.message, 'Deliberate fail'
            done()
        proxy.pipe out


    it 'allows source to be a promise for a stream', ->
        proxy = new Proxy -> Q inp = new TestReadable test, 3
        proxy.pipe out
        out.promise.then ->
            assert.isNotNull inp
            eql out.buf, test
            eql count, 1
