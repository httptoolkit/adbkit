Fs = require 'fs'
Stream = require 'stream'
Async = require 'async'
Promise = require 'bluebird'
Sinon = require 'sinon'
Chai = require 'chai'
Chai.use require 'sinon-chai'
{expect, assert} = Chai

Adb = require '../../'
Sync = require '../../src/adb/sync'
Stats = require '../../src/adb/sync/stats'
Entry = require '../../src/adb/sync/entry'
PushTransfer= require '../../src/adb/sync/pushtransfer'
PullTransfer = require '../../src/adb/sync/pulltransfer'

# This test suite is a bit special in that it requires a connected Android
# device (or many devices). All will be tested.
describe 'Sync', ->

  SURELY_EXISTING_FILE = '/system/build.prop'
  SURELY_EXISTING_PATH = '/'
  SURELY_NONEXISTING_PATH = '/non-existing-path'
  SURELY_WRITABLE_FILE = '/data/local/tmp/_sync.test'

  client = null
  deviceList = null

  forEachSyncDevice = (iterator, done) ->
    assert deviceList.length > 0,
      'At least one connected Android device is required'
    Async.each deviceList, (device, callback) ->
      client.syncService device.id
        .then (sync) ->
          expect(sync).to.be.an.instanceof Sync
          iterator sync, (err) ->
            sync.end()
            callback err
    , done

  before (done) ->
    client = Adb.createClient()
    client.listDevices()
      .then (devices) ->
        deviceList = devices
        done()

  describe 'end()', ->

    it "should end the sync connection", (done) ->
      forEachSyncDevice (sync, callback) ->
        sync.connection.on 'end', ->
          callback()
        sync.end()
      , done

  describe 'push(contents, path[, mode][, callback])', ->

    it "should call pushStream when contents is a Stream", (done) ->
      forEachSyncDevice (sync, callback) ->
        stream = new Stream.PassThrough
        spy = Sinon.spy sync, 'pushStream'
        transfer = sync.push stream, SURELY_WRITABLE_FILE
        transfer.cancel()
        expect(spy).to.have.been.called
        callback()
      , done

    it "should call pushFile when contents is a String", (done) ->
      forEachSyncDevice (sync, callback) ->
        spy = Sinon.spy sync, 'pushFile'
        transfer = sync.push 'foo.bar', SURELY_WRITABLE_FILE
        transfer.cancel()
        expect(spy).to.have.been.called
        callback()
      , done

    it "should return a PushTransfer instance", (done) ->
      forEachSyncDevice (sync, callback) ->
        stream = new Stream.PassThrough
        rval = sync.push stream, SURELY_WRITABLE_FILE
        expect(rval).to.be.an.instanceof PushTransfer
        rval.cancel()
        callback()
      , done

  describe 'pushStream(stream, path[, mode][, callback])', ->

    it "should return a PushTransfer instance", (done) ->
      forEachSyncDevice (sync, callback) ->
        stream = new Stream.PassThrough
        rval = sync.pushStream stream, SURELY_WRITABLE_FILE
        expect(rval).to.be.an.instanceof PushTransfer
        rval.cancel()
        callback()
      , done

    it "should be able to push >65536 byte chunks without error", (done) ->
      forEachSyncDevice (sync, callback) ->
        stream = new Stream.PassThrough
        content = new Buffer 1000000
        transfer = sync.pushStream stream, SURELY_WRITABLE_FILE
        transfer.on 'error', callback
        transfer.on 'end', callback
        stream.write content
        stream.end()
      , done

  describe 'pull(path, callback)', ->

    it "should retrieve the same content pushStream() pushed", (done) ->
      forEachSyncDevice (sync, callback) ->
        stream = new Stream.PassThrough
        content = 'ABCDEFGHI' + Date.now()
        transfer = sync.pushStream stream, SURELY_WRITABLE_FILE
        expect(transfer).to.be.an.instanceof PushTransfer
        transfer.on 'error', callback
        transfer.on 'end', ->
          transfer = sync.pull SURELY_WRITABLE_FILE
          expect(transfer).to.be.an.instanceof PullTransfer
          transfer.on 'error', callback
          transfer.on 'readable', ->
            expect(transfer.read().toString()).to.equal content
            callback()
        stream.write content
        stream.end()
      , done

    it "should return a PullTransfer instance", (done) ->
      forEachSyncDevice (sync, callback) ->
        rval = sync.pull SURELY_EXISTING_FILE
        expect(rval).to.be.an.instanceof PullTransfer
        rval.cancel()
        callback()
      , done

    describe 'Stream', ->

      it "should emit 'end' when pull is done", (done) ->
        forEachSyncDevice (sync, callback) ->
          transfer = sync.pull SURELY_EXISTING_FILE
          transfer.on 'end', callback
          transfer.resume()
        , done

  describe 'stat(path, callback)', ->

    it "should return a Promise", (done) ->
      forEachSyncDevice (sync, callback) ->
        rval = sync.stat SURELY_EXISTING_PATH
        expect(rval).to.be.an.instanceof Promise
        rval.then ->
          callback()
      , done

    it "should call with an ENOENT error if the path does not exist", (done) ->
      forEachSyncDevice (sync, callback) ->
        sync.stat SURELY_NONEXISTING_PATH
          .then (stats) ->
            callback new Error 'Should not reach success branch'
          .catch (err) ->
            expect(err).to.be.an.instanceof Error
            expect(err.code).to.equal 'ENOENT'
            expect(err.errno).to.equal 34
            expect(err.path).to.equal SURELY_NONEXISTING_PATH
            callback()
      , done

    it "should call with an fs.Stats instance for an existing path", (done) ->
      forEachSyncDevice (sync, callback) ->
        sync.stat SURELY_EXISTING_PATH
          .then (stats) ->
            expect(stats).to.be.an.instanceof Fs.Stats
            callback()
      , done

    describe 'Stats', ->

      it "should implement Fs.Stats", (done) ->
        expect(new Stats 0, 0, 0).to.be.an.instanceof Fs.Stats
        done()

      it "should set the `.mode` property for isFile() etc", (done) ->
        forEachSyncDevice (sync, callback) ->
          sync.stat SURELY_EXISTING_FILE
            .then (stats) ->
              expect(stats).to.be.an.instanceof Fs.Stats
              expect(stats.mode).to.be.above 0
              expect(stats.isFile()).to.be.true
              expect(stats.isDirectory()).to.be.false
              callback()
        , done

      it "should set the `.size` property", (done) ->
        forEachSyncDevice (sync, callback) ->
          sync.stat SURELY_EXISTING_FILE
            .then (stats) ->
              expect(stats).to.be.an.instanceof Fs.Stats
              expect(stats.isFile()).to.be.true
              expect(stats.size).to.be.above 0
              callback()
        , done

      it "should set the `.mtime` property", (done) ->
        forEachSyncDevice (sync, callback) ->
          sync.stat SURELY_EXISTING_FILE
            .then (stats) ->
              expect(stats).to.be.an.instanceof Fs.Stats
              expect(stats.mtime).to.be.an.instanceof Date
              callback()
        , done

    describe 'Entry', ->

      it "should implement Stats", (done) ->
        expect(new Entry 'foo', 0, 0, 0).to.be.an.instanceof Stats
        done()

      it "should set the `.name` property", (done) ->
        forEachSyncDevice (sync, callback) ->
          sync.readdir SURELY_EXISTING_PATH
            .then (files) ->
              expect(files).to.be.an 'Array'
              files.forEach (file) ->
                expect(file.name).to.not.be.null
                expect(file).to.be.an.instanceof Entry
              callback()
        , done

      it "should set the Stats properties", (done) ->
        forEachSyncDevice (sync, callback) ->
          sync.readdir SURELY_EXISTING_PATH
            .then (files) ->
              expect(files).to.be.an 'Array'
              files.forEach (file) ->
                expect(file.mode).to.not.be.null
                expect(file.size).to.not.be.null
                expect(file.mtime).to.not.be.null
              callback()
        , done
