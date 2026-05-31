#version 450

// Hard-coded positions for a triangle
vec2 positions[3] = vec2[](
        vec2(0.0, -0.5), // Top
        vec2(0.5, 0.5), // Bottom Right
        vec2(-0.5, 0.5) // Bottom Left
    );

vec3 colors[3] = vec3[](
        vec3(1.0, 0.0, 0.0), // Red
        vec3(0.0, 1.0, 0.0), // Green
        vec3(0.0, 0.0, 1.0) // Blue
    );

// Output to the fragment shader
layout(location = 0) out vec3 fragColor;

void main() {
    // Get position for the current vertex (index 0, 1, or 2)
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);

    // Pass color to fragment shader
    fragColor = colors[gl_VertexIndex];
}