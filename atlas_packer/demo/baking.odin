#+private file
package demo

import "core:fmt"
import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
vec2i::[2]i32

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

@(private="package")
baking_state :State = {
    init,
    finit,
    nil,
    draw,
}

ATLAS_SIZE :vec2i: {512, 512}
Sprite :: struct {
    size: Vector2,
    tex_pos:[]Vector2,
}

// Used as dynamic atlas
render_texture:rl.RenderTexture
player_texture: rl.Texture2D
// Holds data about source texture
player_sprite_source:Sprite = {{16,16}, {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}}}
// Holds data about generated atlas texture, assigned to spawned instances
player_tex_pos:[]Vector2
player_sprite_instance:Sprite

reset_atlas :: proc() {
	rl.UnloadRenderTexture(render_texture)
	render_texture = rl.LoadRenderTexture(ATLAS_SIZE.x, ATLAS_SIZE.y)
}

init :: proc(){
    reset_atlas()
    player_texture = rl.LoadTexture("../assets/textures/player_sheet.png")
    player_tex_pos = make_slice([]Vector2, len(player_sprite_source.tex_pos))
    // Spawned instance
    player_sprite_instance.tex_pos = player_tex_pos

    // Init packer
    rc: stbrp.Context
    rc_nodes: [ATLAS_SIZE.x]stbrp.Node
    stbrp.init_target(&rc, ATLAS_SIZE.x, ATLAS_SIZE.x, raw_data(rc_nodes[:]), ATLAS_SIZE.x)

    // Prepare rectangle list for packing
    pack_rects:[dynamic]stb_Rect
    for i:int = 0; i < len(player_sprite_source.tex_pos); i += 1 {
        append(&pack_rects, stb_Rect {
            id = cast(i32)i,
            w = stbrp.Coord(player_sprite_source.size.x),
            h = stbrp.Coord(player_sprite_source.size.y),
        })
    }

    // Packing
    rect_pack_res := stbrp.pack_rects(&rc, raw_data(pack_rects), i32(len(pack_rects)))
    if rect_pack_res != 1 {
        fmt.printf("Failed packing \n")
        return
    }

    // Update positions on generated atlas
    for i:int = 0; i < len(pack_rects); i += 1 {
        rect:^stb_Rect = &pack_rects[i]
        id:i32 = rect.id
        tex_pos:Vector2 = {cast(f32)rect.x, cast(f32)rect.y}
        player_tex_pos[id] = tex_pos
    }

    // Raylib's render texture is flipped vertically
    // Use temporary first then draw it on target render texture
    temp_render_texture: = rl.LoadRenderTexture(ATLAS_SIZE.x, ATLAS_SIZE.y)
    defer rl.UnloadRenderTexture(temp_render_texture)

    // Draw sprite tiles to render target
    rl.BeginTextureMode(temp_render_texture)
    
    // Render player sprites on generated atlas
    source_rect:[4]f32 = {0,0, player_sprite_source.size.x, player_sprite_source.size.y}
    for i:int = 0; i < len(player_sprite_source.tex_pos); i += 1 {
        source_rect.xy = player_sprite_source.tex_pos[i].xy

        dest_pos:Vector2 = player_tex_pos[i]
        rl.DrawTextureRec(player_texture, transmute(Rectangle)source_rect, dest_pos, rl.WHITE)
    }

    rl.EndTextureMode()

    // Transfer to target render_texture to flip it correclty
    rl.BeginTextureMode(render_texture)
    rl.DrawTexture(temp_render_texture.texture, 0, 0, rl.WHITE)
    rl.EndTextureMode()
}

finit :: proc() {
	rl.UnloadRenderTexture(render_texture)
    rl.UnloadTexture(player_texture)
    delete(player_tex_pos)
}

draw :: proc(){
    rect:Rectangle = {10, 10, cast(f32)ATLAS_SIZE.x, cast(f32)ATLAS_SIZE.y}
    source_rect:Rectangle = {0, 0, rect.width, rect.height}
    dest_rect:Rectangle = {10, 10, rect.width, rect.height}

    rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)
    rl.DrawTexturePro(render_texture.texture, source_rect, dest_rect, {0,0}, 0.0, rl.WHITE)

    // Test player tex_pos
    rect_player:Rectangle = {player_tex_pos[0].x, player_tex_pos[0].y, player_sprite_source.size.x, player_sprite_source.size.y}
    rl.DrawRectangleLinesEx({530, 10, rect_player.width, rect_player.height}, 1, rl.BLACK)
    rl.DrawTextureRec(render_texture.texture, rect_player, {530, 10}, rl.WHITE)
}