shader_type spatial;
// Mer animée : vagues en sommets, vaguelettes et écume par pixel, reflets du ciel et du soleil par le moteur.

uniform float time_s = 0.0;
uniform vec3 deep : source_color = vec3(0.05, 0.4, 0.55);
uniform vec3 light : source_color = vec3(0.4, 0.8, 0.95);
uniform float detail = 1.0;

varying vec3 wpos;

float wave(vec2 p) {
	return sin(p.x * 0.11 + time_s * 0.7) * 0.7 + sin(p.y * 0.16 - time_s * 0.55) * 0.55
		+ sin((p.x + p.y) * 0.29 + time_s * 1.2) * 0.28 + sin((p.x - p.y) * 0.47 - time_s * 1.6) * 0.14;
}

float ripple(vec2 p) {
	return sin(p.x * 1.9 + time_s * 2.3) * sin(p.y * 2.3 - time_s * 1.9) * 0.05
		+ sin((p.x * 0.8 - p.y * 1.3) * 3.1 + time_s * 3.1) * 0.025;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(w.xz);
	wpos = w;
}

void fragment() {
	vec2 p = wpos.xz;
	float h = wave(p);
	float e = 0.6;
	vec3 n = vec3(wave(p - vec2(e, 0.0)) - wave(p + vec2(e, 0.0)), 2.0 * e, wave(p - vec2(0.0, e)) - wave(p + vec2(0.0, e)));
	float e2 = 0.15;
	// les vaguelettes s'estompent au loin pour éviter le scintillement
	float near = detail * clamp(1.0 - length(VERTEX) / 70.0, 0.0, 1.0);
	n.x += (ripple(p - vec2(e2, 0.0)) - ripple(p + vec2(e2, 0.0))) * (e / e2) * near;
	n.z += (ripple(p - vec2(0.0, e2)) - ripple(p + vec2(0.0, e2))) * (e / e2) * near;
	n = normalize(n);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 c = mix(deep, light, smoothstep(-1.2, 1.5, h));
	// écume sur les crêtes, déchiquetée par les vaguelettes
	float foam = smoothstep(1.3, 1.65, h + ripple(p * 2.0) * 1.5 * near);
	c = mix(c, vec3(1.0), foam * 0.75);
	ALBEDO = c;
	ROUGHNESS = mix(0.14, 0.5, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
