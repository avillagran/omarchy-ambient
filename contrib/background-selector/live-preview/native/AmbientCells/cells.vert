#version 440
layout(location = 0) in vec4 vertexCoord;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec4 vertexColor;
layout(location = 0) out vec2 texCoord;
layout(location = 1) out vec4 color;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
void main() {
    texCoord = vertexTexCoord;
    color = vertexColor * qt_Opacity;
    gl_Position = qt_Matrix * vertexCoord;
}
