#version 330
// The vertex shader of the font glue for the OpenGL backend of Karl2D: the same inputs as its default shader.
layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texcoord;
layout(location = 2) in vec4 color;
uniform mat4 view_projection;
out vec2 fragEm;
flat out int fragSlot;
flat out int fragColor;

void main()
{
    fragEm = texcoord;
    fragSlot = int(color.r * 255.0 + 0.5) + 256 * int(color.g * 255.0 + 0.5);
    fragColor = int(color.b * 255.0 + 0.5);
    gl_Position = view_projection * vec4(position, 1.0);
}
