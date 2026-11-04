#version 440
layout(location = 0) in vec2 texCoord;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D atlas;
// Coverage is all or nothing, so a glyph keeps its exact colour.
void main() {
    fragColor = color * texture(atlas, texCoord).a;
}
