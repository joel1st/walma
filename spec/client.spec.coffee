
{Client} = require "../lib/client"
{EventEmitter} = require "events"

describe "client", ->
  beforeEach ->
    @fakeSocket = new EventEmitter
    @client = new Client @fakeSocket,
      id: "sdfsda"
      userAgent: "sdafds"

  it "can be created", ->
    expect(@client.id).toBeDefined()

  it "emits draws", ->
    asyncSpecWait()
    @client.on "draw", (draw) ->
      expect(draw.user).toEqual "epeli"
      asyncSpecDone()

    @fakeSocket.emit "draw",
      user: "epeli"

  it "emits disconects", ->
    asyncSpecWait()
    @client.on "disconect", (client) =>
      expect(client).toBe @client
      asyncSpecDone()

    @fakeSocket.emit "disconect"

  it "can change state", ->
    initialState = @client.state
    setTimeout =>
      @fakeSocket.emit "state", "teststate"
    , 5

    waitsFor ->
      @client.state isnt initialState

    runs ->
      expect(@client.state).toEqual "teststate"

  it "can be asked for bitmap", ->
    asyncSpecWait()

    # Browser simulator
    @fakeSocket.on "getbitmap", =>
      @fakeSocket.emit "bitmap", "bitmapdata"

    @client.fetchBitmap (err, data) ->
      expect(err).toBeFalsy()
      expect(data).toEqual "bitmapdata"
      asyncSpecDone()

  it "bitmap request can timeout", ->
    asyncSpecWait()
    @client.timeoutTime = 50
    @client.fetchBitmap (err, data) ->
      expect(err.reason).toEqual "timeout"
      expect(data).toBeUndefined()
      asyncSpecDone()


