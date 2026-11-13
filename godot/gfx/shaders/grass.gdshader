shader_type spatial;
render_mode cull_disabled;
// Herbe : brins dégradés du pied à la pointe, qui ondulent au vent par vagues qui traversent le terrain.
// La normale reste verticale : les brins s'éclairent comme le sol et ne scintillent pas.

uniform vec3 base : source_color = vec3(0.35, 0.7, 0.3);
uniform vec3 tip : source_color = vec3(0.75, 0.95, 0.5);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = UV.y * UV.y;
	float gust = sin(w.x * 0.35 + w.z * 0.2 - TIME * 1.8) * 0.5 + 0.5;
	vec2 wind = vec2(0.09 + gust * 0.1, 0.04) + vec2(sin(TIME * 4.0 + w.x * 3.0), cos(TIME * 3.3 + w.z * 3.0)) * 0.025;
	// décalage voulu en coordonnées monde, ramené dans le repère de l'instance (rotation et échelle à peu près uniformes)
	mat3 b = mat3(MODEL_MATRIX);
	VERTEX += transpose(b) * vec3(wind.x, 0.0, wind.y) / dot(b[0], b[0]) * k;
}

void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = mix(base, tip, UV.y);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = tip * 0.3;
}
