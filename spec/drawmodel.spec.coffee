
{EventEmitter} = require "events"
async = require "async"
_  = require 'underscore'

{Db, Connection, Server} = require "mongodb"
{Drawing} = require "../lib/drawmodel"

{Client} = require "../lib/client"
model = require "../lib/drawmodel"


class FakeSocket extends EventEmitter
  join: ->

prepare = (cb) ->
  this.db = db = new Db 'whiteboard-test',
    new Server "localhost", Connection.DEFAULT_PORT,
      auto_reconnect: true

  db.open (err) ->
    throw err if err
    db.dropDatabase (err, done) ->
      cb()

  # db.open  do ->
  #   count = 0
  #   (err, db )->

  #     if ++count isnt 1
  #       console.log "Called twice open", err
  #       cb null
  #       return

  #     if err
  #       console.log "Could not open the db", err
  #       cb err
  #     else
  #       cb null
  #       db.dropDatabase (err, result) -> cb()

beforeEach ->
  asyncSpecWait()
  prepare.call this, ->
    asyncSpecDone()

afterEach ->
  this.db.close ->


describe "Just playing with mongodb driver.", ->

  it "has it", ->
    expect(this.db).toBeTruthy()

  it "can insert", ->
    asyncSpecWait()
    db = this.db
    async.series [
      (cb) ->
        db.collection "testingcollection", (err, coll) ->
          throw err if err
          coll.insert
            name: "foobar"
          , (err) ->
            cb()
      (cb) ->
        db.collection "testingcollection", (err, coll) ->
          coll.update name: "foobar",
            $push:
              foo:
                x: 100
                y: 200
                op: "move"
          , (err) ->
            cb()
      (cb) ->
        db.collection "testingcollection", (err, coll) ->
          coll.find(name: "foobar").nextObject (err, doc) ->
            throw err if err
            expect(doc.foo?[0].x).toBe 100
            cb()
    ], ->
      asyncSpecDone()



describe "Drawing in MongoDB", ->

  beforeEach ->
    asyncSpecWait()
    this.db.collection "testdrawings", (err, coll) =>
      throw err if err
      Drawing.collection = coll
      Drawing.db = this.db
      asyncSpecDone()

  it "can be created", ->
    drawing = new Drawing "test"

  it "gets initialized if not existing", ->
    asyncSpecWait()
    drawing = new Drawing "not existing"
    drawing.fetch (err, doc) ->
      expect(err).toBeFalsy()
      expect(doc.created).toBeTruthy()
      expect(doc.history).toEqual []
      asyncSpecDone()

  it "does not create twice", ->
    asyncSpecWait()
    drawing = new Drawing "test2"
    drawing.fetch (err, doc) =>
      throw err if err
      expect(doc.created).toBeTruthy()
      drawing2 = new Drawing "test2"
      drawing2.fetch (err, doc2) ->
        throw err if err
        expect(doc2.created).toEqual doc.created
        asyncSpecDone()

  it "can append draws", ->
    asyncSpecWait()
    name = "test3"
    drawing = new Drawing name
    drawing.fetch (err, doc) =>
      throw err if err
      created = doc.created
      expect(doc.created).toBeTruthy()
      drawing.addDraw
        shape:
          moves: [
            op: "move"
            x: 100
            y: 200 ]
      , {id: "fakeclient"}
      , (err) =>
        throw err if err
        drawing3 = new Drawing name
        drawing3.fetch (err, doc) =>
          throw err if err
          expect(doc.history[0]).toEqual
            shape:
              moves: [
                op: "move"
                x: 100
                y: 200 ]

          expect(doc.created).toBe created, "the document should not change"
          asyncSpecDone()

  it "initializes client with empty history", ->
    fakeSocket = new FakeSocket

    client = new Client fakeSocket,
      id: "testclient"
      userAgent: "sdafds"

    drawing = new Drawing "init_test"
    drawing.init()

    asyncSpecWait()

    fakeSocket.on "start", (history) ->
      expect(_.isArray history).toBe false
      expect(history.draws.length).toBe 0
      expect(history.latestCachePosition).toBeUndefined()
      asyncSpecDone()

    drawing.addClient client
    expect(_.size drawing.clients).toBe 1

  it "initialized client with small history", ->
    asyncSpecWait()
    fakeSocket = new FakeSocket

    client = new Client fakeSocket,
      id: "smallhistory2"
      userAgent: "sdafds"

    testHistory = null
    fakeSocket.on "start", (history) ->
      expect(_.isArray history.draws).toBe true
      expect(history.draws.length).toBe testHistory.length
      # expect(history).toEqual testHistory
      asyncSpecDone()

    drawing = new Drawing "smallhistory2"
    drawing.cacheInterval = 10
    drawing.fetch ->
      testHistory = for i in [0...2]
        drawing.addDraw draw = {
          shape: {
            color: '#000000',
            tool: 'Pencil',
            size: 50,
            moves: [ { x: i, x: 10, op: "down" }, { x: i, x: 10*i, op: "up" } ], }
          user: 'Esa3',
          time: 1319195315736 }
        , client, (err) ->
          throw err if err

        draw


    setTimeout ->
      drawing.addClient client
    , 300





  it "send draws to the database via clients", ->
    fakeSocket = new FakeSocket

    client = new Client fakeSocket,
      id: "testclient2"
      userAgent: "sdafds"
    drawing = new Drawing "emittest"
    drawing.addClient client

    spyOn(drawing, "addDraw")

    fakeSocket.emit "draw",
      user: "epeli"
      shape:
        moves: []

    expect(drawing.addDraw).toHaveBeenCalled()

  it "asks for cache bitmap from time to time", ->
    fakeSocket = new FakeSocket

    client = new Client fakeSocket,
      id: "ask cache"
      userAgent: "sdafds"
    client.timeoutTime = 50


    drawing = new Drawing "cachetest"
    drawing.init()
    drawing.addClient client

    spyOn client, "fetchBitmap"

    for i in [0...150]
      fakeSocket.emit "draw",
        user: "epeli"
        shape:
          moves: []

    asyncSpecWait()

    setTimeout ->
      expect(client.fetchBitmap).toHaveBeenCalled()
      asyncSpecDone()
    , 500


  it "saves cache point when asked", ->
    fakeSocket = new FakeSocket

    fakeSocket.on "getbitmap", ->
      fakeSocket.emit "bitmap",
        pos: 3
        data: "sdfadfas"

    client = new Client fakeSocket,
      id: "cache save test"
      userAgent: "sdafds"


    drawing = new Drawing "cache point test"
    drawing.init()
    drawing.cacheInterval = 100
    drawing.addClient client


    spyOn drawing, "setCache"

    for i in [0...150]
      fakeSocket.emit "draw",
        user: "epeli"
        shape:
          moves: []

    asyncSpecWait()

    setTimeout ->
      expect(drawing.setCache).toHaveBeenCalledWith 3, "sdfadfas"
      expect(drawing.setCache.callCount).toEqual 1
      asyncSpecDone()
    , 500



  it "can save cache points", ->
    drawing = new Drawing "cache_point_save"
    drawing.fetch ->
      testData = "mytestpicdata"

      asyncSpecWait()
      mydata = null

      drawing.setCache 5, testData , (err, result) ->
        throw err if err

        expect(err).toBeFalsy()

        drawing.getLatestCachePosition (err, position) ->
          throw err if err
          expect(err).toBeFalsy()
          expect(position).toEqual 5
          asyncSpecDone()


  it "finds latest cache point", ->
    testMe = null
    lastData = null
    waitsFor -> testMe isnt null
    runs ->
      bitmap = testMe
      expect(bitmap).toBeDefined()
      expect(bitmap).toEqual 91

    drawing = new Drawing "latest_cache_point"
    drawing.fetch ->

      pointsGenerators = for i in [1...100] by 10 then do (i) ->
        (cb) ->
          drawing.setCache i, lastData = "picturedata#{ i }"
          , (err) ->
            expect(err).toBeFalsy()
            return cb? err if err
            cb null

      async.series pointsGenerators, (err) ->
        expect(err).toBeFalsy()
        drawing.getLatestCachePosition (err, position) ->
          expect(err).toBeFalsy()
          testMe = position

  it "persists cache data", ->
    asyncSpecWait()
    drawing = new Drawing "cache_persist_test"
    drawing.cacheInterval = 10
    drawing.fetch ->
      drawing.setCache 5, "foobar", (err) ->
        expect(err).toBeFalsy()
        drawing.getCache 5, (err, data) ->
          expect(err).toBeFalsy()
          expect(data.toString()).toEqual "foobar", "should get the saved data from cache"
          asyncSpecDone()


  it "gets only partial history when picture is cached", ->
    testHistory = null
    waitsFor -> testHistory isnt null
    runs ->
      expect(testHistory.latestCachePosition).toBeDefined "should have cache"

      expect(testHistory.latestCachePosition).toBe 10, "last cache pos should be 10"

      expect(testHistory.draws).toBeDefined "should have draws"

      expect(testHistory.draws.length).toEqual 5, "should have 5 draws"

      expect(_.last(_.last(testHistory.draws).shape.moves).x).toEqual 15, "last draw x should be 15"

    fakeSocket = new FakeSocket

    client = new Client fakeSocket,
      id: "partial_history_client"
      userAgent: "sdafds"

    counter = 0

    fakeSocket.on "getbitmap", ->
      fakeSocket.emit "bitmap",
        pos: counter
        data: "partialcachepic"

    fakeSocket.on "start", (history) ->
      testHistory = history

    drawing = new Drawing "partial_history_drawing"
    drawing.cacheInterval = 10
    drawing.fetch ->
      for i in [1...16]
        counter += 1
        drawing.addDraw draw = {
          shape: {
            color: '#000000',
            tool: 'Pencil',
            size: 50,
            moves: [ { x: i, x: 10, op: "down" }, { x: i, x: i, op: "up" } ], }
          user: 'Esa3',
          time: 1319195315736 }
        , client, (err) ->
          throw err if err

        draw

      setTimeout ->
        drawing.addClient client
      , 400


  it "knows the size of canvas", ->
    asyncSpecWait()
    drawingName = "canvasize"

    fakeSocket = new FakeSocket
    client = new Client fakeSocket,
      id: "canvas_size"
      userAgent: "sdafds"

    drawing = new Drawing drawingName
    drawing.cacheInterval = 10
    drawing.fetch ->
      drawers = for i in [0...20] then do (i) -> (cb) ->
        drawing.addDraw draw = {
          shape: {
            color: '#000000',
            tool: 'Pencil',
            size: 50,
            moves: [ { x: i, y: 10, op: "down" }, { x: i, y: 10*i, op: "up" } ], }
          user: 'Esa',
          time: 1319195315736 }
        , client, cb

      async.series drawers, (err) ->
        throw err if err
        expect(drawing.resolution).toEqual { x: 19, y: 190 }, "resolution is set when draws are added"

        d2 = new Drawing drawingName
        d2.fetch ->
          expect(d2.resolution).toEqual { x: 19, y: 190 }, "resolution is set when drawing is loaded from db"
          asyncSpecDone()



