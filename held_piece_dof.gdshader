shader_type canvas_item;
render_mode unshaded, blend_mix;

// Desfoque de profundidade aplicado somente à peça segurada.
//
// A peça fica na frente da mão (plano da mão), mas pertence ao tabuleiro: o
// raio vem da profundidade da célula alvo, com a mesma rampa do DOF da câmera.
// A máscara da peça (PIECE_LAYER, já gerada pelo OcclusionOutline) limita o
// efeito — a mão e o resto da tela não são tocados.
//
// A tela já chega renderizada com o DOF do mundo; aqui só borramos os pixels
// da silhueta da peça com uma espiral de amostras.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D piece_mask : hint_default_black;
uniform float blur_radius_px = 0.0;

const int SAMPLE_COUNT = 16;
const float GOLDEN_ANGLE = 2.39996323;

void fragment() {
	float coverage = texture(piece_mask, SCREEN_UV).a;
	// Fora da silhueta da peça o frame original permanece intacto.
	if (coverage < 0.02) {
		discard;
	} else {
		vec3 sharp = texture(screen_texture, SCREEN_UV).rgb;
		vec3 blurred = sharp;
		if (blur_radius_px >= 0.5) {
			float weight = 1.0;
			for (int i = 0; i < SAMPLE_COUNT; i++) {
				float t = (float(i) + 0.5) / float(SAMPLE_COUNT);
				float radius = sqrt(t) * blur_radius_px;
				float angle = float(i) * GOLDEN_ANGLE;
				vec2 offset = vec2(cos(angle), sin(angle)) * radius * SCREEN_PIXEL_SIZE;
				blurred += texture(screen_texture, SCREEN_UV + offset).rgb;
				weight += 1.0;
			}
			blurred /= weight;
		}

		// Mistura só dentro da máscara (borda dura o bastante para não invadir
		// a mão nem o tabuleiro ao redor).
		float blend = smoothstep(0.15, 0.65, coverage);
		COLOR = vec4(mix(sharp, blurred, blend), 1.0);
	}
}
