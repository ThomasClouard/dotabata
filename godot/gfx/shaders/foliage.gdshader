shader_type spatial;
// Feuillage au vent : le haut de chaque boule (houppier, buisson) se balance, avec un petit frémissement.
// La phase dépend de la position dans le monde, pour que les arbres ne bougent pas tous ensemble.

uniform vec3 albedo : source_color = vec3(0.32, 0.84, 0.5);
uniform float sway = 0.08;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = dot(o.xz, vec2(0.37, 0.23));
	float t = TIME;
	// hauteur dans la boule : 0 en bas, 1 en haut (sommets d'une sphère de rayon 1)
	float k = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	k *= k;
	vec3 wind = vec3(sin(t * 1.3 + ph) + 0.4 * sin(t * 2.9 + ph * 1.7), 0.0, 0.5 * sin(t * 1.1 + ph * 0.6));
	vec3 flutter = vec3(0.0, sin(t * 7.0 + VERTEX.x * 6.0 + ph) * 0.15, 0.0);
	// le décalage est voulu en mètres : on compense l'échelle du nœud
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += (wind * k + flutter * k) * sway / sc;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	RIM = 0.35;
	RIM_TINT = 0.7;
	// un peu de lumière qui traverse les feuilles
	BACKLIGHT = albedo * 0.35;
}
