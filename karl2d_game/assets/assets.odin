package assets

ASSETS_DIR :: "../../assets/"
TEXTURES_DIR :: ASSETS_DIR + "textures/"
SOUNDS_DIR :: ASSETS_DIR + "sounds/"
MUSIC_DIR :: ASSETS_DIR + "music/"
FONTS_DIR :: ASSETS_DIR + "fonts/"
DATA_DIR :: ASSETS_DIR + "data/"


// FONTS
font_pixellocale :: #load(FONTS_DIR + "pixellocale-v-1-4.ttf")

// TEXTURES
CHARACTERS_DIR :: TEXTURES_DIR + "characters/"
VFX_DIR :: TEXTURES_DIR + "vfx/"
PROJECTILE_DIR :: TEXTURES_DIR + "projectile/"
WEAPON_DIR :: TEXTURES_DIR + "weapon/"

texture_char_plumber :: #load(CHARACTERS_DIR + "plumber_16x16_strip8.png")
texture_char_electrician :: #load(CHARACTERS_DIR + "electrician_16x16_strip8.png")
texture_char_zomby_walker :: #load(CHARACTERS_DIR + "zombie_16x16_strip8.png")
// texture_char_zomby_crawler :: #load(CHARACTERS_DIR + "zombie_crawler_16x16_strip6-sheet.png")
// texture_weapon_pistol :: #load(WEAPON_DIR + "gun_0.png")
texture_weapon_shotgun :: #load(WEAPON_DIR + "gun_1.png")
// texture_weapon_asault :: #load(WEAPON_DIR + "gun_3.png")
// texture_weapon_sword :: #load(WEAPON_DIR + "sword_0.png")
texture_projectile_bullet1 :: #load(PROJECTILE_DIR + "bullet_1.png")