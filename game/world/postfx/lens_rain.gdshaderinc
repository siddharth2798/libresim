// Rain on an outside camera's lens (included by screen_post.gdshader). Drops sit in a jittered grid of cells;
// each comes and goes on its own clock. Parked or slow they bead; with airspeed they run along `flow` and
// stretch into streaks. A drop refracts: the view inside it is sampled from a flipped, shrunken neighbourhood,
// with a darker rim and a small highlight, like water on glass. Returns (uv offset xy, rim shade, coverage).

float lr_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 lr_layer(vec2 uv, float aspect, float cell, float amount, float run, vec2 flow, float t, float seed) {
	vec2 q = vec2(uv.x * aspect, uv.y) / cell;
	vec2 dir = normalize(flow);
	// drops run along the flow: shift each lane (column across the flow) at its own speed
	vec2 side = vec2(-dir.y, dir.x);
	float lane = floor(dot(q, side));
	float speed = run * (0.5 + lr_hash(vec2(lane, seed)));
	q -= dir * t * speed;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = lr_hash(id + seed);
	float life = fract(t * (0.08 + 0.1 * h) + h * 7.0);  // appear, stay, dry off
	if (h > amount * 0.9 || life > 0.85) {
		return vec4(0.0);
	}
	vec2 c = (vec2(lr_hash(id + 3.1 + seed), lr_hash(id + 5.7 + seed)) - 0.5) * 0.5;
	vec2 d = f - c;
	float stretch = 1.0 + 2.5 * clamp(run, 0.0, 1.0);  // streaks at speed
	float along = dot(d, dir);
	float across = dot(d, side);
	float r = (0.12 + 0.12 * lr_hash(id + 9.3 + seed)) * (1.0 - 0.6 * life);
	float e = length(vec2(along / stretch, across)) / r;
	if (e >= 1.0) {
		return vec4(0.0);
	}
	float cover = smoothstep(1.0, 0.75, e);
	vec2 off = -(d / r) * cell * 0.6 * vec2(1.0 / aspect, 1.0);  // a lens: the view inside is flipped and squeezed
	return vec4(off, smoothstep(0.6, 1.0, e), cover);
}

// amount 0..1, speed: airspeed m/s (streaks from ~20 m/s), aspect: width / height.
vec4 lens_rain(vec2 uv, float aspect, float amount, float speed, float t) {
	float run = clamp(speed / 40.0, 0.0, 1.5);
	vec2 flow = vec2(0.25, 1.0);  // down the lens, a little sideways (screen y grows downwards)
	vec4 a = lr_layer(uv, aspect, 0.06, amount, run * 1.4 + 0.02, flow, t, 0.0);
	vec4 b = lr_layer(uv, aspect, 0.035, amount, run * 2.0 + 0.03, flow, t, 17.0);
	return a.w >= b.w ? a : b;
}
