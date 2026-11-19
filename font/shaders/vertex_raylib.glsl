#version 330
// The vertex shader of the font glue for raylib: the position in pixels, the em coordinates in the texture coordinate and the slot of the glyph in the red and green of the vertex color.
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 fragEm;
flat out int fragSlot;

void main()
{
    fragEm = vertexTexCoord;
    fragSlot = int(vertexColor.r * 255.0 + 0.5) + 256 * int(vertexColor.g * 255.0 + 0.5);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
