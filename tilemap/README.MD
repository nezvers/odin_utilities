# Tilemap
Designed to not allocate but work on provided slices. Meaning user can manage allocations or use predefined buffers.   
Very flexible and hackable API.

`odin run demo`

Provides `raylib` implementation and demo example for integration with drawing and data management.

## TileAtlas
Represents information about used texture. It holds 2D position slice.

## Tile
Abstraction layer that represents tile. It holds ID slice for alternative tiles. ID can be mapped to other abstractions, but designed to map to TileAtlas texture positions.

## Tileset
Abstraction layer that represents Tile collection. It holds slice of Tiles that can be accessed by using TileID.

## Tilemap
Abstraction layer that represents a map layer. It holds slice of TileID that can be mapped to Tileset, Tile or TileAtlas.