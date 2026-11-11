shader_type canvas_item;
render_mode unshaded, blend_mix;

// Adaptado do outline original do Seed (Kode Game Studio).
// Recebe duas máscaras de tela (mão e peça) e desenha o contorno apenas
// ao redor da interseção — a parte da peça que está sobre a mão.
// A outra parte da peça (fora da silhueta da mão) fica sem contorno.

uniform vec4 outline_color : source_color = vec4(1.0, 0.6, 0.0, 1.0);
uniform int outline_size : hint_range(1, 5) = 2;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform sampler2D hand_mask : hint_default_black;
uniform sampler2D piece_mask : hint_default_black;


bool covered(vec2 uv) {
	float hand = texture(hand_mask, uv).a;
	float piece = texture(piece_mask, uv).a;
	return hand > alpha_threshold && piece > alpha_threshold;
}


void fragment() {
	vec4 result = vec4(0.0);

	// Dentro da parte coberta não desenha nada (a peça/mão continuam visíveis).
	if (!covered(SCREEN_UV)) {
		// Fora da cobertura: se algum vizinho está coberto, desenha o contorno.
		vec2 px = SCREEN_PIXEL_SIZE;
		bool hit = false;
		for (int x = -outline_size; x <= outline_size; x++) {
			for (int y = -outline_size; y <= outline_size; y++) {
				if (hit || (x == 0 && y == 0)) {
					continue;
				}
				vec2 offset = vec2(float(x), float(y)) * px;
				if (covered(SCREEN_UV + offset)) {
					hit = true;
				}
			}
		}
		if (hit) {
			result = outline_color;
		}
	}

	COLOR = result;
}
