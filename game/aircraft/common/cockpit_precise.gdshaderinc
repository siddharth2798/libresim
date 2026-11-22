// Camera-relative cockpit position (aircraft/common/cockpit_precision.gd). Godot's single-precision renderer forms
// VIEW * MODEL on the GPU from render-space transforms; in cruise the camera is ~11 km up (render y = altitude), where
// float32 steps are ~1 mm, so the cockpit, 0.6-0.9 m from the eye, jittered by up to ~0.1 deg a frame. In the cockpit
// camera's own pass CKPT_PRECISE_MODELVIEW (first line of vertex()) takes the translation from small numbers instead:
// ckpt_view (camera from aircraft, every frame) times this mesh's aircraft-local origin (instance uniform; w = 1 once
// CockpitPrecision has set it). Shadow passes, other cameras and every mesh without the origin keep the engine's.
global uniform mat4 ckpt_view;
global uniform vec3 ckpt_cam;
global uniform float ckpt_on;
instance uniform vec4 ckpt_origin = vec4(0.0);
#define CKPT_PRECISE_MODELVIEW if (!IN_SHADOW_PASS && ckpt_on > 0.5 && ckpt_origin.w > 0.5 && distance(INV_VIEW_MATRIX[3].xyz, ckpt_cam) < 0.05) { MODELVIEW_MATRIX[3] = ckpt_view * vec4(ckpt_origin.xyz, 1.0); }
