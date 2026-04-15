# Runtime texture packing
    
Example how to bake sprites and textures into single texture for draw call optimization.    
Use case for each scene collect relevant textures, sprites, fonts.    
Current limitiation is one-shot packing - pre-allocate rectangle slice buffer for one texture, can't overflow to multiple textures.    