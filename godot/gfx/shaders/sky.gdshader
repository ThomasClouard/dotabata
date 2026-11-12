shader_type sky;
// Ciel de fin d'après-midi : dégradé profond au zénith, horizon lumineux et doré du côté du soleil, soleil stylisé
// (disque net, anneau doux, grand halo). Sert aussi de source de lumière ambiante et de reflets.

uniform vec3 top_color : source_color = vec3(0.3, 0.55, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.5, 0.4, 0.42);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.62);

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float h = clamp(d.y, -1.0, 1.0);
	float s = max(dot(d, sd), 0.0);
	// côté soleil : l'horizon se réchauffe (dorée) ; à l'opposé, il reste frais
	float side = max(dot(normalize(d.xz + 1e-4), normalize(sd.xz)), 0.0);
	vec3 hz = mix(horizon_color, mix(horizon_color, sun_color, 0.55), side * side);
	vec3 c = mix(hz, top_color, pow(smoothstep(0.0, 0.75, h), 0.65));
	// bande claire juste au-dessus de l'horizon
	c += vec3(1.0) * exp(-abs(h) * 18.0) * 0.06;
	c = mix(c, horizon_color * 0.95, smoothstep(0.0, -0.3, h));
	// grand halo et voile doré autour du soleil
	c += sun_color * (pow(s, 6.0) * 0.18 + pow(s, 40.0) * 0.35);
	if (!AT_CUBEMAP_PASS) {
		// disque net et anneau doux, façon dessin animé
		c += sun_color * smoothstep(0.9994, 0.9997, s) * 8.0;
		c += sun_color * smoothstep(0.996, 0.9985, s) * (1.0 - smoothstep(0.9988, 0.9993, s)) * 0.6;
	}
	COLOR = c;
}
