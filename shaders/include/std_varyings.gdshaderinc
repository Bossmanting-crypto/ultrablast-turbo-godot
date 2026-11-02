// STD_VERT of the web build: object-space position, world position and world normal.
// Varyings can only be written inside vertex(), so this is a macro: put STD_VERTEX; at the top of vertex().
varying vec3 vP;
varying vec3 vW;
varying vec3 vN;
#define STD_VERTEX vP = VERTEX; vW = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; vN = normalize(mat3(MODEL_MATRIX)*NORMAL)
