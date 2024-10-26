#version 330 core

in vec3 position;
out vec4 color;

void main()
{
  // normalise the position such that it scales from 0 to 1
  vec3 pos = (position + 0.5f) / 1.0f;
  color = vec4(1-pos.x, pos.yx, 1.0f);
}
