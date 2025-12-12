local TurtleConfig = {}

function TurtleConfig.fromPayload(payload)
    return {
        turtleName = payload.turtleName,
        chunkNumber = payload.chunkNumber,
        chunkCoordinates = payload.chunkCoordinates,
        chestCoordinates = payload.chestCoordinates,
        currentChunkDepth = payload.currentChunkDepth,
        startDirection = payload.startDirection,
        maxDepth = payload.maxDepth,
        trash = payload.trash
    }
end

return TurtleConfig
