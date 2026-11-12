shader_type spatial;
render_mode unshaded, fog_disabled;
// Nuages moelleux, sans calcul d'éclairage : blancs et dorés côté soleil, dessous rosé-lavande, bord lumineux.

uniform vec3 sun_dir = vec3(0.5, 0.4, 0.42);
uniform vec3 lit : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 warm : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 shade : source_color = vec3(0.78, 0.76, 0.93);

varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wn);
	float sun = dot(n, normalize(sun_dir));
	// dessous à l'ombre, dessus éclairé ; le côté soleil se réchauffe
	float up = smoothstep(-0.6, 0.7, n.y);
	vec3 c = mix(shade, lit, up);
	c = mix(c, warm, smoothstep(0.2, 1.0, sun) * 0.55);
	// bord lumineux (lumière qui traverse les franges du nuage)
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	c += warm * rim * 0.35;
	ALBEDO = c;
}
