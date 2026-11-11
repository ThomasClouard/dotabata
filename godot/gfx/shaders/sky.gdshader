shader_type sky;
// Ciel en dégradé avec un soleil doux ; sert aussi de source de lumière ambiante et de reflets.

uniform vec3 top_color : source_color = vec3(0.3, 0.55, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.45, 0.8, 0.35);

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, -1.0, 1.0);
	vec3 c = mix(horizon_color, top_color, pow(smoothstep(0.0, 0.85, h), 0.7));
	c = mix(c, horizon_color * 0.96, smoothstep(0.0, -0.35, h));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	// voile de brume lumineuse autour du soleil, puis le disque lui-même
	c += vec3(1.0, 0.93, 0.75) * (pow(s, 28.0) * 0.35 + pow(s, 4.0) * 0.12);
	if (!AT_CUBEMAP_PASS) {
		c += vec3(1.0, 0.93, 0.75) * pow(s, 900.0) * 6.0;
	}
	COLOR = c;
}
