shader_type spatial;
render_mode cull_disabled;
// Peau des personnages, façon jouet en vinyle : efface les fragments situés dans les sphères d'impact (liseré foncé
// au bord), déforme les membres en tubes de Bézier et le corps (penché, écrasé) directement dans le vertex shader.

uniform vec3 albedo : source_color = vec3(1.0);
uniform vec4 hits[12];
// membres : départ, point de contrôle, extrémité (repère du personnage) et rayons (début, fin)
uniform vec3 limb_a[4];
uniform vec3 limb_c[4];
uniform vec3 limb_e[4];
uniform vec2 limb_r[4];
// corps (sommets marqués UV2.x = -1) : hauteurs y0, y1, décalage du haut (courbe en t²), écrasement (1 = neutre)
uniform vec2 body_y = vec2(0.5, 1.6);
uniform vec2 body_bend = vec2(0.0);
uniform float body_squash = 1.0;

varying vec3 wpos;

void vertex() {
	if (UV2.x < -0.5) {
		float h = body_y.y - body_y.x;
		float t = clamp((VERTEX.y - body_y.x) / h, 0.0, 1.0);
		// écrasement à volume à peu près constant : plus bas, plus large au milieu
		float k = mix(1.0, inversesqrt(body_squash), sin(PI * t));
		VERTEX.xz *= k;
		VERTEX.y = body_y.x + (VERTEX.y - body_y.x) * body_squash;
		VERTEX.xz += body_bend * (t * t);
		// la normale suit la pente de la courbure (décalage horizontal dérivé selon y)
		NORMAL.y -= dot(NORMAL.xz, body_bend) * 2.0 * t / h;
		NORMAL = normalize(NORMAL);
	}
	int li = int(UV2.x + 0.5);
	if (li > 0) {
		vec3 a = limb_a[li - 1];
		vec3 c = limb_c[li - 1];
		vec3 e = limb_e[li - 1];
		float r0 = limb_r[li - 1].x;
		float r1 = limb_r[li - 1].y;
		float k = UV.x; // numéro de l'anneau : 0..9 le long de la courbe, 10..13 calotte du bout
		float t = min(1.0, k / 9.0);
		float u = 1.0 - t;
		vec3 p = a * (u * u) + c * (2.0 * u * t) + e * (t * t);
		vec3 tg = a * (-2.0 * u) + c * (2.0 * u - 2.0 * t) + e * (2.0 * t);
		if (dot(tg, tg) < 1e-8) tg = e - a;
		if (dot(tg, tg) < 1e-8) tg = vec3(0.0, -1.0, 0.0);
		tg = normalize(tg);
		// une Bézier quadratique est plane : la normale du plan donne un repère sans vrillage
		vec3 bn = cross(c - a, e - c);
		if (dot(bn, bn) < 1e-10) bn = cross(vec3(0.0, 0.0, 1.0), tg);
		if (dot(bn, bn) < 1e-10) bn = cross(vec3(1.0, 0.0, 0.0), tg);
		bn = normalize(bn - tg * dot(bn, tg));
		vec3 nn = cross(bn, tg);
		float r = mix(r0, r1, t);
		float tilt = 0.0;
		if (k > 9.5) {
			float phi = (k - 9.0) / 4.0 * PI * 0.5;
			p += tg * (r1 * sin(phi));
			r = r1 * cos(phi);
			tilt = sin(phi);
		}
		vec3 d = nn * cos(UV.y) + bn * sin(UV.y);
		VERTEX = p + d * r;
		NORMAL = normalize(d * sqrt(1.0 - tilt * tilt) + tg * tilt);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = albedo;
	float edge = 0.0;
	for (int i = 0; i < 12; i++) {
		vec4 h = hits[i];
		if (h.w > 0.0) {
			vec3 d = wpos - h.xyz;
			// bord irrégulier, façon trou de dessin animé
			float wob = sin(d.x * 31.0 + d.y * 17.0) * sin(d.y * 29.0 + d.z * 23.0) * sin(d.z * 19.0 + d.x * 13.0);
			float dist = length(d) + wob * 0.045;
			if (dist < h.w) {
				discard;
			}
			if (dist < h.w + 0.04) {
				edge = 1.0;
			}
		}
	}
	if (edge > 0.5) {
		col *= 0.2;
	}
	if (!FRONT_FACING) {
		col *= 0.3;
	}
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	// contour lumineux bleuté (lumière du ciel qui rase les bords), visible même à l'ombre
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.55, 0.75, 1.0) * fres * 0.22 * (FRONT_FACING ? 1.0 : 0.0) * (1.0 - edge);
}

// Éclairage « vinyle » : la lumière déborde dans l'ombre avec une teinte chaude (comme une matière un peu
// translucide), et un reflet net de vernis.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	vec3 warm = mix(vec3(1.0, 0.55, 0.5), vec3(1.0), smoothstep(0.0, 0.6, wrap));
	DIFFUSE_LIGHT += wrap * warm * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, hv), 0.0), 80.0) * smoothstep(0.0, 0.15, ndl);
	SPECULAR_LIGHT += vec3(spec) * ATTENUATION * LIGHT_COLOR * 0.35;
}
